#!/usr/bin/env ruby

# Simplified CLI interface for choosing $instances and running commands on them

require 'aws-sdk-ssm'
require 'aws-sdk-ec2'
require 'tty-prompt'
require 'tty-spinner'
require 'colorize'
require 'optparse'


$options = {}

unless $stdin.tty? and !$options.has_key?(:commands)
  $options[:commands] = $stdin.read.split('\n')
end

OptionParser.new do |opts|
  opts.banner = "Usage: hotfix.rb [options]"

  opts.on("-i NAME", "--instances=NAME", "Instance name(s) comma-seperated (e.g., development-web,development-worker)") do |i|
    $options[:instances] = i.split(',')
  end

  opts.on("-c COMMANDS", "--commands=COMMANDS", "Run custom commands (can also be redirected in like `ruby hotfix.rb < mycommands.sh`") do |c|
    $options[:commands] = c.split('\n')
  end

  opts.on("-d VERSION","--deploy=VERSION", "Version to deploy") do |d|
    $options[:deploy_version] = d
  end

  opts.on("-r REPOURL", "--repo=REPOURL", "Full URL to git repo to deploy from (use in conjunction with -d)") do |r|
    $options[:repo_url] = r
  end

  opts.on("-k /path/to/key","--key=/path/to/key", "Path to private key to use") do |k|
    $options[:key] = k
  end

  opts.on("-k /path/to/key","--key=/path/to/key", "Path to public key to use") do |k|
    $options[:pub_key] = k
  end

  opts.on_tail("-h", "--help", "Show this message") do
    puts opts
    exit
  end
end.parse!


$ssm = Aws::SSM::Client.new
ec2 = Aws::EC2::Resource.new
$prompt = TTY::Prompt.new(interrupt: :signal)

trap "INT" do
  puts "\n\nOperation canceled".red
  exit 130
end


ids = $ssm.describe_instance_information.instance_information_list.map(&:instance_id)

$instances = ec2.instances(instance_ids: ids).map do |i|
  name = i.tags.detect { |t| t.key == 'Name' }

  next unless name

  {
    :name => name.value,
    :id => i.id
  }
end

$instances.sort_by! { |a| a[:name] }

def choose_operation
  return 3 if $options.has_key?(:commands)
  return 5 if $options.has_key?(:deploy_version)
  $prompt.select("Select operation to run:") do |menu|
    menu.choice "Start SSH session (via SSM)", 1
    menu.choice "Start portforwarding session (via SSM)", 2
    menu.choice "Run custom command(s)", 3
    menu.choice "Install pub key", 4
    menu.choice "Deploy hotfix", 5
    menu.choice "Exit", 0
  end
end


def choose_instances(selection_style)
  $prompt.send(selection_style, "Select server(s) to run operation on:") do |menu|
    $instances.each do |i|
      menu.choice i[:name], i[:id]
    end
  end
end

def prompt_for_user
  loop do
    user = $prompt.ask("Enter user to install for:", default: "ubuntu")

    return user if user.size > 0

    puts "Invalid user"
  end
end

def get_public_key
  loop do
    if $options.has_key?(:pub_key)
      key_file = $options[:pub_key]
    else
      key_file = $prompt.ask("Enter path of pub key:", default: "#{ENV['HOME']}/.ssh/id_rsa.pub")
    end

    return `cat #{key_file}` if File.file?(key_file)

    puts "Invalid path to public key"
  end
end

def get_deploy_key
  loop do
    if $options.has_key?(:key)
      key_file = $options[:key]
    else
      key_file = $prompt.ask("Enter path of deploy key:", default: "#{ENV['HOME']}/.ssh/id_rsa")
    end

    return `cat #{key_file}` if File.file?(key_file)

    puts "Invalid path to deploy key"
  end
end

# operation = $prompt.select("Select deployment operation:") do |menu|
#   menu.choice "Normal deployment", 1,  disabled: "(Under construction)"
#
#   if selected.count != 1
#     menu.choice "Database migration", 2, disabled: "(Can only be performed on one instance)".light_black
#   else
#     menu.choice "Database migration", 2,  disabled: "(Under construction)"
#   end
#   menu.choice "Run command(s)", 3
# end

# def standard_deploy(key, version)
#   deploy_dir = "deploy-#{Time.now.to_i}"
#
#   [
#     "sudo su - deploy",
#     "cd /opt/deployed",
#     "echo \"#{key}\" > deploy.key",
#     "chmod 600 deploy.key",
#     "ssh-agent bash -c 'ssh-add deploy.key; sudo -u deploy GIT_SSH_COMMAND=\"ssh -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no\" git clone #{REPO_URL} #{deploy_dir}'",
#     "rm deploy.key",
#     "cd #{deploy_dir}",
#     "sudo -u deploy git checkout #{version}",
#     "sudo -u deploy cp ../threads/config/database.yml ./config/database.yml",
#     "sudo -u deploy cp ../threads/config/application.yml ./config/application.yml",
#     "sudo -u deploy bundle install",
#     "sudo -u deploy bundle binstubs puma --path ./sbin"
#   ]
# end
#
#

def get_repo_url
  return $options[:repo_url] if $options.has_key?(:repo_url)

  loop do
    url = $prompt.ask("Enter repo URL :")

    return url if url.size > 0

    puts "Invalid URL"
  end
end

def get_deploy_version
  return $options[:deploy_version] if $options.has_key?(:deploy_version)

  loop do
    version = $prompt.ask("Enter branch/tag to deploy :")

    return version if version.size > 0

    puts "Invalid version"
  end
end

def deploy_version(key, repo_url, version)
  base_dir = "/opt/deployed/"
  deploy_dir = "new"

  [
    "sudo su - deploy",
    "cd /opt/deployed",
    "echo \"#{key}\" > /home/deploy/.ssh/id_rsa",
    "chmod 600 /home/deploy/.ssh/id_rsa",
    "chown deploy:www-data /home/deploy/.ssh/id_rsa",
    "sudo rm -rf #{base_dir}#{deploy_dir}",
    "sudo -H -u deploy bash -c 'git clone -b #{version} #{repo_url} #{base_dir}#{deploy_dir}'",
    "rm /home/deploy/.ssh/id_rsa",
    "sudo -H -u deploy bash -c 'cd #{base_dir}#{deploy_dir} && ./bin/bundle install --deployment'",
    "sudo -H -u deploy bash -c 'cp #{base_dir}threads/config/database.yml #{base_dir}#{deploy_dir}/config/database.yml'",
    "sudo -H -u deploy bash -c 'cp #{base_dir}threads/config/application.yml #{base_dir}#{deploy_dir}/config/application.yml'",
    "sudo -H -u deploy bash -c 'cd #{base_dir}#{deploy_dir}/doc/render_perf_chart && npm install'",
    "sudo -H -u deploy bash -c 'cd #{base_dir}#{deploy_dir} && ./bin/rake assets:precompile'",
    "sudo rm -rf #{base_dir}/old",
    "sudo -H -u deploy bash -c 'mv #{base_dir}/current #{base_dir}/old'",
    "sudo -H -u deploy bash -c 'mv #{base_dir}/new #{base_dir}/current'",
    "sudo systemctl is-active --quiet delayed_job@0 && systemctl restart delayed_job@{0..3}",
    "sudo systemctl is-active --quiet puma && systemctl restart puma",
    "sudo rm -rf /opt/deployed/threads"
  ]
end

def operate(operation, selected)
  case operation
  when 1
    selected = selected.kind_of?(Array) ? selected.first : selected
    exec("aws ssm start-session --target #{selected}")
  when 2
    selected = selected.kind_of?(Array) ? selected.first : selected
    exec("aws ssm start-session --target #{selected} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"22\"],\"localPortNumber\":[\"9999\"]}'")
  when 3
    if $options.has_key?(:commands)
      commands = $options[:commands]
    else
      commands = $prompt.multiline("Enter commands")
    end
  when 4
    key = get_public_key
    user = prompt_for_user
    commands = [
      "sudo -u #{user} echo \"#{key}\" >> /home/#{user}/.ssh/authorized_keys"
    ]
  when 5
    key = get_deploy_key
    repo_url = get_repo_url
    version = get_deploy_version
    commands = deploy_version(key, repo_url, version)
  end

  puts ""
  $prompt.keypress("Press any key to start (Deployment starts in :countdown seconds)", timeout: 10) unless $options.has_key?(:commands)

  selected = [*selected]

  cmd_resp = $ssm.send_command({
                                instance_ids: selected,
                                document_name: "AWS-RunShellScript",
                                parameters: {
                                  "commands": commands
                                }
                              })


  invocation = {}

  spinners = TTY::Spinner::Multi.new("[:spinner] Deployment")

  selected.each do |s|
    i = $instances.detect { |j| j[:id] == s }

    i[:spinner] = spinners.register "[:spinner] #{i[:name].cyan}"
  end

  puts ""

  $instances.each { |i| i.has_key?(:spinner) ? i[:spinner].auto_spin : nil }

  loop do

    sleep 3

    invocation = $ssm.list_command_invocations(command_id: cmd_resp.command.command_id)

    invocation.command_invocations.each do |ci|
      i = $instances.detect { |j| j[:id] == ci.instance_id }

      if ci.status == "Success"
        i[:spinner].success
      end

      next if ci.status == "InProgress" or ci.status == "Pending"

      i[:spinner].error(ci.status)
    end

    statuses = invocation.command_invocations.map(&:status)

    break unless statuses.include?("InProgress") or statuses.include?("Pending")
  end

  puts ""
  puts ""

  invocation.command_invocations.each do |ci|
    status = ci.status == "Success" ? ci.status.green : ci.status

    puts "#{$instances.detect { |i| i[:id] == ci.instance_id }[:name].cyan}: #{status}"

    cmd = $ssm.get_command_invocation(command_id: ci.command_id, instance_id: ci.instance_id)

    if cmd.standard_output_content.size > 0

      puts "STDOUT:".white.underline
      puts ""
      puts cmd.standard_output_content.light_white
    end

    if cmd.standard_error_content.size > 0

      puts "STDERR:".red.underline
      puts ""
      puts cmd.standard_error_content.light_red
    end

  end
end

def main
  operation = choose_operation

  exit if operation == 0

  selection_style = (operation == 1 || operation == 2) ? :select : :multi_select

  if $options.has_key?(:instances)
    selected = $instances.select { |i| $options[:instances].include?(i[:name]) }.map{ |i| i[:id] }
  else
    selected = choose_instances(selection_style)
  end

  if selected.empty?
    puts "No instances selected"
    exit
  end

  operate(operation, selected)
end

main

