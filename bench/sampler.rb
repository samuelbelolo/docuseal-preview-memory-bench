# frozen_string_literal: true

# Prints one JSON line per sample of a container's cgroup v2 memory files, read from outside the container.
#
#   ruby sampler.rb <container id> [interval_seconds] [cgroup root, default /cg]
#
# Finds the container directory under the cgroup root: docker/<id> (Docker Desktop, cgroupfs) or
# system.slice/docker-<id>.scope (systemd hosts).

require 'json'

id = ARGV.fetch(0)
interval = Float(ARGV.fetch(1, '0.25'))
root = ARGV.fetch(2, '/cg')
dir = Dir.glob(["#{root}/**/#{id}", "#{root}/**/docker-#{id}.scope"]).find { |path| File.exist?(File.join(path, 'memory.current')) }
abort "no cgroup directory with memory.current for #{id} under #{root}" unless dir
$stdout.sync = true

read = ->(name) { File.read(File.join(dir, name)) }

loop do
  stat = read.call('memory.stat').lines.to_h { |line| line.split.then { |key, value| [key, value.to_i] } }
  events = read.call('memory.events').lines.to_h { |line| line.split.then { |key, value| [key, value.to_i] } }

  puts JSON.generate(
    t: Process.clock_gettime(Process::CLOCK_REALTIME).round(3),
    current: read.call('memory.current').to_i,
    peak: read.call('memory.peak').to_i,
    anon: stat['anon'],
    file: stat['file'],
    oom_kill: events['oom_kill']
  )

  sleep interval
rescue Errno::ENOENT
  puts JSON.generate(t: Process.clock_gettime(Process::CLOCK_REALTIME).round(3), gone: true)
  break
end
