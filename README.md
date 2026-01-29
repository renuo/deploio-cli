# deploio-cli (deploio / depl)

A CLI for [Deploio](https://www.deplo.io/) that wraps [`nctl`](https://github.com/ninech/nctl) commands with a simpler interface.

## Requirements

- Ruby 3.3+
- nctl version 1.10.0 or higher

## Installation

### From source (development)

```bash
git clone https://github.com/renuo/deploio-cli.git
cd deploio-cli
bundle install
bundle exec bin/deploio --help
```

### As a gem (coming soon)

```bash
gem install deploio-cli
```

## Shell Completion

Enable autocompletion by adding this to your `~/.zshrc` or `~/.bashrc`, or whatever you use:

```bash
eval "$(deploio completion)"
```

After setup, completions work for:
- Commands: `deploio <TAB>` → shows all commands and subcommands
- Options: `deploio logs --<TAB>` → shows --tail, --lines, --app, etc.
- Apps (dynamic): `deploio logs --app <TAB>` → fetches available apps from server

## Configuration

### App naming convention

Apps are referenced using `<project>-<app>` format, where:
- `project` is your Deploio project name (e.g., `deploio-landing-page`)
- `app` is the environment/app name (e.g., `develop`, `production`)

Example: `deploio-landing-page-develop`

### Automatic app detection

When you run a command without `--app`, the CLI will automatically detect the app by matching your git remote URL against nctl apps:

```bash
cd ~/projects/deploio-landing-page
deploio logs --tail  # Automatically detects app from git remote
```

If multiple apps match (e.g., develop and production), you'll be prompted to select one.

## Usage

```
deploio - CLI for Deploio (wraps nctl)

AUTHENTICATION
  deploio auth:login              Authenticate with nctl
  deploio auth:logout             Log out
  deploio auth:whoami             Show current user and organization
  deploio login                   Shortcut for auth:login

APPS
  deploio apps                    List all apps
  deploio apps -p PROJECT         List apps in a specific project
  deploio apps:info -a APP        Show app details

PROJECTS
  deploio projects                List all projects

BUILDS
  deploio builds                  List all builds
  deploio builds -a APP           List builds for a specific app

SERVICES
  deploio services                            List all services
  deploio services -p PROJECT                 List services in a specific project
  deploio services -p PROJECT --url List services with connection URLs (requires -p)
  deploio services -p PROJECT --connected-apps  Show which apps use each service (requires -p)
  deploio services --chf                    Show estimated monthly price (CHF) for each service

LOGS
  deploio logs -a APP             Show recent logs
  deploio logs -a APP --tail      Stream logs continuously
  deploio logs -a APP -n 200      Show last N lines

EXECUTION
  deploio exec -a APP -- CMD      Run command in app container
  deploio run -a APP -- CMD       Alias for exec

OTHER
  deploio completion              Generate shell completion script
  deploio version                 Show version

FLAGS
  -a, --app APP                   App in <project>-<app> format
  -o, --org ORG                   Organization
  --dry-run                       Print commands without executing
  --no-color                      Disable colored output
```

## Examples

### Authentication

```bash
# Login to nctl
deploio login

# Check current user
deploio auth:whoami
```

### Working with apps

```bash
# List all apps
deploio apps

# Show app info
deploio apps:info -a myproject-staging

```

### Logs and execution

```bash
# View logs
deploio logs -a deploio-landing-page-develop

# Stream logs
deploio logs -a deploio-landing-page-develop --tail

# Run a command
deploio exec -a deploio-landing-page-develop -- rails console

# With git remote matching (auto-detected)
cd ~/projects/deploio-landing-page
deploio logs --tail
deploio exec -- rails console
```

## Development

### Running tests

```bash
bundle exec rake test
```

### Building the gem

```bash
gem build deploio-cli.gemspec
```

### Testing commands

The best way to test the commands in the shell is to temporarly set:

```shell
export PATH="$PWD/bin:$PATH"
```

to have the `deploio` command binded to the current one, and

```shell
eval "$(deploio completion)"
```

to refresh the autocompletion options.

## License

MIT

## Copyright

Renuo AG
