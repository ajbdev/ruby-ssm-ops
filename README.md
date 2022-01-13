# ssm-ops

A simple ruby script for managing AWS SSM (Systems Manager) inventoried instances.

### Installation

Download the script and run `bundle install` wherever you downloaded it.

### Usage

```
Usage: ssm-ops.rb [options]
-i, --instances=NAME             Instance name(s) comma-seperated (e.g., development-web,development-worker)
-c, --commands=COMMANDS          Run custom commands (can also be redirected in like `ruby hotfix.rb < mycommands.sh`
-h, --help                       Show this message
```
You can also pipe commands in via STDIN:

```
echo "uptime" | ruby ssm-ops.rb
```

Providing no options opens the program in interactive mode.

### Interactive mode

Interactive mode comes with the following few prebaked operations:

```
Select operation to run: 
‣ Start SSH session (via SSM)
  Start portforwarding session (via SSM)
  Run custom command(s)
  Install pub key
  Exit
```
