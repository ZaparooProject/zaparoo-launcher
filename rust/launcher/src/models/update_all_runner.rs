// Zaparoo Launcher
// Copyright (c) 2026 Wizzo Pty Ltd and the Zaparoo Project contributors.
// SPDX-License-Identifier: LicenseRef-PolyForm-Noncommercial-1.0.0
//
// `Browse.UpdateAllRunner` — prototype PTY bridge for MiSTer's
// update_all script. QML owns the modal and forwards D-pad/keyboard
// input; this singleton owns the child process, terminal output, and
// final status.

use cxx_qt::{CxxQtType, Threading};
use cxx_qt_lib::QString;
use std::ffi::CString;
use std::path::Path;
use std::pin::Pin;
use std::thread;
use tracing::{error, info, warn};

const SCRIPT_PATH: &str = "/media/fat/Scripts/update_all.sh";
const STATE_IDLE: i32 = 0;
const STATE_RUNNING: i32 = 1;
const STATE_SUCCESS: i32 = 2;
const STATE_ERROR: i32 = 3;
const OUTPUT_CAP_BYTES: usize = 32 * 1024;

pub struct UpdateAllRunnerRust {
    state: i32,
    output_text: QString,
    error_message: QString,
    exit_code: i32,
    input_fd: i32,
    child_pid: i32,
}

impl Default for UpdateAllRunnerRust {
    fn default() -> Self {
        Self {
            state: STATE_IDLE,
            output_text: QString::default(),
            error_message: QString::default(),
            exit_code: -1,
            input_fd: -1,
            child_pid: -1,
        }
    }
}

#[cxx_qt::bridge]
pub mod ffi {
    unsafe extern "C++" {
        include!("model_includes.h");

        type QString = cxx_qt_lib::QString;
    }

    unsafe extern "RustQt" {
        #[qobject]
        #[qml_element]
        #[qml_singleton]
        #[qproperty(i32, state)]
        #[qproperty(QString, output_text)]
        #[qproperty(QString, error_message)]
        #[qproperty(i32, exit_code)]
        type UpdateAllRunner = super::UpdateAllRunnerRust;

        #[qinvokable]
        fn run(self: Pin<&mut UpdateAllRunner>);

        #[qinvokable]
        fn reset(self: Pin<&mut UpdateAllRunner>);

        #[qinvokable]
        fn send_input(self: Pin<&mut UpdateAllRunner>, input: QString);
    }

    impl cxx_qt::Threading for UpdateAllRunner {}
}

impl ffi::UpdateAllRunner {
    fn run(mut self: Pin<&mut Self>) {
        if self.state == STATE_RUNNING {
            return;
        }
        self.as_mut().set_state(STATE_RUNNING);
        self.as_mut().set_output_text(QString::from(format!("$ {SCRIPT_PATH}\n").as_str()));
        self.as_mut().set_error_message(QString::default());
        self.as_mut().set_exit_code(-1);
        self.as_mut().rust_mut().input_fd = -1;
        self.as_mut().rust_mut().child_pid = -1;

        let qt_thread = self.qt_thread();
        match spawn_update_all_pty() {
            Ok(child) => {
                self.as_mut().rust_mut().input_fd = child.input_fd;
                self.as_mut().rust_mut().child_pid = child.pid;
                if let Err(e) = thread::Builder::new()
                    .name("zaparoo-update-all-pty".into())
                    .spawn(move || {
                        let mut terminal = TerminalBuffer::new(format!("$ {SCRIPT_PATH}\n"));
                        let mut buf = [0_u8; 4096];
                        loop {
                            // SAFETY: `child.master_fd` is owned by
                            // this thread until the loop exits. `buf`
                            // is valid writable memory for its length.
                            let n = unsafe {
                                libc::read(
                                    child.master_fd,
                                    buf.as_mut_ptr().cast(),
                                    buf.len(),
                                )
                            };
                            if n <= 0 {
                                break;
                            }
                            terminal.push_bytes(&buf[..n as usize]);
                            let snapshot = terminal.snapshot();
                            let _ = qt_thread.queue(move |mut model| {
                                model.as_mut().set_output_text(QString::from(snapshot.as_str()));
                            });
                        }

                        close_fd(child.master_fd);
                        let code = wait_for_child(child.pid);
                        let final_output = terminal.snapshot();
                        let _ = qt_thread.queue(move |mut model| {
                            close_fd(model.as_mut().rust_mut().input_fd);
                            model.as_mut().rust_mut().input_fd = -1;
                            model.as_mut().rust_mut().child_pid = -1;
                            model
                                .as_mut()
                                .set_output_text(QString::from(final_output.as_str()));
                            model.as_mut().set_exit_code(code);
                            if code == 0 {
                                info!("update_all exited successfully");
                                model.as_mut().set_state(STATE_SUCCESS);
                            } else {
                                warn!("update_all exited with code {code}");
                                model.as_mut().set_error_message(QString::from(
                                    format!("Exited with code {code}.").as_str(),
                                ));
                                model.as_mut().set_state(STATE_ERROR);
                            }
                        });
                    })
                {
                    error!("failed to spawn update_all reader thread: {e}");
                    close_fd(self.as_mut().rust_mut().input_fd);
                    self.as_mut().rust_mut().input_fd = -1;
                    self.as_mut()
                        .set_error_message(QString::from("Could not start reader thread."));
                    self.as_mut().set_state(STATE_ERROR);
                }
            }
            Err(e) => {
                warn!("failed to start update_all: {e}");
                self.as_mut()
                    .set_error_message(QString::from(e.as_str()));
                self.as_mut().set_state(STATE_ERROR);
            }
        }
    }

    fn reset(mut self: Pin<&mut Self>) {
        if self.state == STATE_RUNNING {
            return;
        }
        self.as_mut().set_state(STATE_IDLE);
        self.as_mut().set_output_text(QString::default());
        self.as_mut().set_error_message(QString::default());
        self.as_mut().set_exit_code(-1);
        self.as_mut().rust_mut().input_fd = -1;
        self.as_mut().rust_mut().child_pid = -1;
    }

    fn send_input(self: Pin<&mut Self>, input: QString) {
        if self.state != STATE_RUNNING {
            return;
        }
        let fd = self.input_fd;
        if fd < 0 {
            return;
        }
        let bytes = input.to_string().into_bytes();
        if bytes.is_empty() {
            return;
        }
        // SAFETY: `fd` is a live PTY master duplicate while state is
        // RUNNING. `bytes.as_ptr()` is valid for `bytes.len()` during
        // this call. Short writes are acceptable for tiny input tokens
        // (arrow escapes / enter / escape) and the next user press can
        // retry if the child is already gone.
        let written = unsafe { libc::write(fd, bytes.as_ptr().cast(), bytes.len()) };
        if written < 0 {
            warn!("failed to write input to update_all PTY");
        }
    }
}

struct PtyChild {
    pid: i32,
    master_fd: i32,
    input_fd: i32,
}

fn spawn_update_all_pty() -> Result<PtyChild, String> {
    if !Path::new(SCRIPT_PATH).exists() {
        return Err(format!("Script not found: {SCRIPT_PATH}"));
    }

    let mut master_fd: libc::c_int = -1;
    // SAFETY: `forkpty` initializes `master_fd` in the parent and
    // returns twice. Null termios/winsize asks the platform defaults.
    // Child immediately replaces its image with `/bin/sh`.
    let pid = unsafe {
        libc::forkpty(
            &mut master_fd,
            std::ptr::null_mut(),
            std::ptr::null(),
            std::ptr::null(),
        )
    };
    if pid < 0 {
        return Err("forkpty failed.".into());
    }
    if pid == 0 {
        exec_update_all_child();
    }

    // SAFETY: `master_fd` is a valid fd in the parent after successful
    // `forkpty`. A duplicate lets QML write input while the reader
    // thread blocks on the original fd.
    let input_fd = unsafe { libc::dup(master_fd) };
    if input_fd < 0 {
        close_fd(master_fd);
        return Err("dup failed for update_all PTY.".into());
    }

    Ok(PtyChild {
        pid,
        master_fd,
        input_fd,
    })
}

fn exec_update_all_child() -> ! {
    if let Some(parent) = Path::new(SCRIPT_PATH).parent() {
        if let Some(parent_str) = parent.to_str() {
            if let Ok(cwd) = CString::new(parent_str) {
                // SAFETY: `cwd` is a NUL-free C string created above.
                unsafe {
                    libc::chdir(cwd.as_ptr());
                }
            }
        }
    }

    let script = c"/media/fat/Scripts/update_all.sh";
    let bash = c"/bin/bash";
    let bash_arg0 = c"bash";
    let sh = c"/bin/sh";
    let sh_arg0 = c"sh";
    // SAFETY: all argv pointers are valid NUL-terminated strings. Each
    // call either replaces the child process or returns with errno set.
    // Try direct exec first so the script's shebang wins, then fall
    // back through common shells for non-executable script files.
    unsafe {
        libc::execl(
            script.as_ptr(),
            script.as_ptr(),
            std::ptr::null::<libc::c_char>(),
        );
        libc::execl(
            bash.as_ptr(),
            bash_arg0.as_ptr(),
            script.as_ptr(),
            std::ptr::null::<libc::c_char>(),
        );
        libc::execl(
            sh.as_ptr(),
            sh_arg0.as_ptr(),
            script.as_ptr(),
            std::ptr::null::<libc::c_char>(),
        );
        libc::_exit(127);
    }
}

fn wait_for_child(pid: i32) -> i32 {
    let mut status: libc::c_int = 0;
    // SAFETY: `pid` is returned by `forkpty`; `status` points to valid
    // writable memory for wait status.
    let waited = unsafe { libc::waitpid(pid, &mut status, 0) };
    if waited < 0 {
        return -1;
    }
    if libc::WIFEXITED(status) {
        libc::WEXITSTATUS(status)
    } else if libc::WIFSIGNALED(status) {
        -libc::WTERMSIG(status)
    } else {
        -1
    }
}

fn close_fd(fd: i32) {
    if fd < 0 {
        return;
    }
    // SAFETY: closing an fd is safe here; callers only pass fds owned
    // by the runner. Errors are not actionable during teardown.
    unsafe {
        libc::close(fd);
    }
}

#[derive(Debug)]
struct TerminalBuffer {
    text: String,
    esc_state: EscapeState,
    csi: String,
    pending_cr: bool,
}

#[derive(Debug, Default)]
enum EscapeState {
    #[default]
    None,
    Escape,
    Csi,
}

impl TerminalBuffer {
    fn new(seed: String) -> Self {
        Self {
            text: seed,
            esc_state: EscapeState::None,
            csi: String::new(),
            pending_cr: false,
        }
    }

    fn snapshot(&self) -> String {
        self.text.clone()
    }

    fn push_bytes(&mut self, bytes: &[u8]) {
        let chunk = String::from_utf8_lossy(bytes);
        for ch in chunk.chars() {
            self.push_char(ch);
        }
        self.cap();
    }

    fn push_char(&mut self, ch: char) {
        match self.esc_state {
            EscapeState::None => self.push_plain(ch),
            EscapeState::Escape => {
                if ch == '[' {
                    self.csi.clear();
                    self.esc_state = EscapeState::Csi;
                } else {
                    self.esc_state = EscapeState::None;
                }
            }
            EscapeState::Csi => {
                self.csi.push(ch);
                if ('@'..='~').contains(&ch) {
                    self.apply_csi();
                    self.esc_state = EscapeState::None;
                    self.csi.clear();
                }
            }
        }
    }

    fn push_plain(&mut self, ch: char) {
        if self.pending_cr {
            self.pending_cr = false;
            if ch == '\n' {
                self.text.push('\n');
                return;
            }
            self.truncate_current_line();
        }

        match ch {
            '\x1b' => self.esc_state = EscapeState::Escape,
            '\r' => self.pending_cr = true,
            '\n' => self.text.push('\n'),
            '\t' => self.text.push_str("    "),
            ch if ch >= ' ' => self.text.push(ch),
            _ => {}
        }
    }

    fn apply_csi(&mut self) {
        if self.csi.ends_with('J') || self.csi.ends_with('H') || self.csi.ends_with('f') {
            self.text.clear();
        } else if self.csi.ends_with('K') {
            self.truncate_current_line();
        }
    }

    fn truncate_current_line(&mut self) {
        if let Some(pos) = self.text.rfind('\n') {
            self.text.truncate(pos + 1);
        } else {
            self.text.clear();
        }
    }

    fn cap(&mut self) {
        if self.text.len() <= OUTPUT_CAP_BYTES {
            return;
        }
        let keep_from = self.text.len() - OUTPUT_CAP_BYTES;
        let keep_from = self.text[keep_from..]
            .find('\n')
            .map_or(keep_from, |offset| keep_from + offset + 1);
        self.text = self.text[keep_from..].to_string();
    }
}
