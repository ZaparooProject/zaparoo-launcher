# QML Gotchas

Read this when writing or reviewing QML. These are pitfalls `qmllint` only
catches *after* the code is written, so it's cheaper to avoid them up front.

- **Typed properties, not `var`.** Use `list<string>`, `list<url>`, `int`,
  `real`. `var` produces `QVariant` warnings and blocks AOT compilation.

- **`Repeater` delegates need `pragma ComponentBehavior: Bound`** at the top
  of the file. Add `required property int index` to the delegate, plus
  `required property string modelData` when the model is a list.

- **Nested delegate children** that reference the delegate's properties must
  qualify: give the delegate an `id` and use `id.modelData`, not bare
  `modelData`.

- **Singleton QML types** need both `pragma Singleton` in the `.qml` file
  and `set_source_files_properties(Foo.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)`
  in CMake, or qmllint will warn "not declared as singleton in qmldir".

- **Function type annotations required.** Add `: ParamType` parameters and
  `: ReturnType` return types to all functions in singleton `.qml` files.

- **`NumberAnimation on propName`** conflicts with `property T propName: value`.
  Drop the `: value` initializer; the animation takes over immediately.
