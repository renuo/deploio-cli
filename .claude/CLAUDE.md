When specifying the `--app` option, we always want to use the format `<project_name>-<app_name>`.
Also autocompletion should generate the suggestions for app names (for example --app) in the format `<project_name>-<app_name>`.
In deploio there's organizations (orgs). each org has many projects. Each project has many applications (app).
When a command is added or removed or modified, the completion_generator should also be updated accordingly and the README as well.

