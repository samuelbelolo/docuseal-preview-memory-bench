# frozen_string_literal: true

# Summarizes one run directory written by run.sh into summary.json and prints one line.
#
#   ruby summarize.rb results/<label>

require 'json'
require 'digest'

dir = ARGV.fetch(0)
mb = ->(bytes) { bytes && (bytes / 1024.0 / 1024).round }

samples = File.readlines(File.join(dir, 'samples.jsonl')).map do |line|
  JSON.parse(line)
rescue JSON::ParserError
  nil
end.compact
samples.reject! { |s| s['gone'] }
abort "#{dir}: samples.jsonl has no samples (did the sampler find the container cgroup?)" if samples.empty?

uploads = File.readlines(File.join(dir, 'uploads.tsv')).drop(1).map do |line|
  doc, phase, start, finish, http, redirect = line.chomp.split("\t")
  { doc: doc.to_i, phase: phase, start: start.to_f, end: finish.to_f, http: http, redirect: redirect.to_s }
end

container = JSON.parse(File.read(File.join(dir, 'container.json')))

previews = File.readlines(File.join(dir, 'previews.tsv')).map do |line|
  record_id, filename, checksum, key = line.chomp.split("\t")
  { record_id: record_id.to_i, filename: filename, checksum: checksum, key: key }
end

data_dir = File.join(dir, 'data')
disk_mismatches = Dir.exist?(data_dir) ? previews.count do |preview|
  path = File.join(dir, 'data', 'attachments', preview[:key][0, 2], preview[:key][2, 2], preview[:key])
  !File.exist?(path) || Digest::MD5.file(path).base64digest != preview[:checksum]
end : nil

groups = previews.group_by { |p| p[:record_id] }.values
signatures = groups.map { |group| Digest::MD5.hexdigest(group.map { |p| "#{p[:filename]}:#{p[:checksum]}" }.join(',')) }
orders_ok = groups.all? { |group| group.map { |p| p[:filename] } == Array.new(group.size) { |i| "#{i}.png" } }

window = lambda do |from, to|
  slice = samples.select { |s| s['t'] >= from && s['t'] <= to }
  slice.empty? ? nil : slice
end

first_start = uploads.first && uploads.first[:start]
rest = first_start && window.call(first_start - 5, first_start)
median = ->(values) { values.sort[values.size / 2] }

docs = uploads.map do |upload|
  slice = window.call(upload[:start], upload[:end] + 0.5) || []
  {
    doc: upload[:doc],
    phase: upload[:phase],
    ok: upload[:http] == '302' && upload[:redirect].match?(%r{/templates/\d+/edit}),
    seconds: (upload[:end] - upload[:start]).round(1),
    peak_current_mb: mb.call(slice.map { |s| s['current'] }.max),
    peak_anon_mb: mb.call(slice.map { |s| s['anon'] }.max),
    end_anon_mb: mb.call(slice.last&.dig('anon'))
  }
end

sequential = docs.select { |d| d[:phase] == 'sequential' && d[:ok] }
parallel = uploads.select { |u| u[:phase] == 'parallel' }

summary = {
  label: File.basename(dir),
  settings: File.read(File.join(dir, 'settings.txt')).strip,
  rest_anon_mb: rest && mb.call(median.call(rest.map { |s| s['anon'] })),
  rest_current_mb: rest && mb.call(median.call(rest.map { |s| s['current'] })),
  memory_peak_mb: mb.call(samples.map { |s| s['peak'] }.max),
  max_anon_mb: mb.call(samples.map { |s| s['anon'] }.max),
  final_anon_mb: mb.call(samples.last&.dig('anon')),
  oom_kill_events: samples.map { |s| s['oom_kill'].to_i }.max,
  oom_killed: container['oom_killed'],
  exit_code: container['exit_code'],
  uploads_ok: docs.count { |d| d[:ok] },
  uploads_sent: docs.size,
  sequential_seconds: sequential.map { |d| d[:seconds] },
  sequential_mean_seconds: sequential.empty? ? nil : (sequential.sum { |d| d[:seconds] } / sequential.size).round(1),
  parallel_wall_seconds: parallel.size == 2 ? (parallel.map { |u| u[:end] }.max - parallel.map { |u| u[:start] }.min).round(1) : nil,
  previews_per_document: groups.map(&:size),
  preview_signatures: signatures.uniq,
  preview_order_ok: orders_ok,
  disk_md5_mismatches: disk_mismatches,
  documents: docs
}

File.write(File.join(dir, 'summary.json'), JSON.pretty_generate(summary))

puts format(
  '%<label>s: rest %<rest>s MB, memory.peak %<peak>s MB, max anon %<anon>s MB, OOM %<oom>s (events %<events>s), ' \
  'ok %<ok>s/%<sent>s, seq %<seq>s s (mean %<mean>s), parallel %<par>s s, previews %<previews>s, sig %<sig>s',
  label: summary[:label], rest: summary[:rest_anon_mb], peak: summary[:memory_peak_mb],
  anon: summary[:max_anon_mb], oom: summary[:oom_killed], events: summary[:oom_kill_events],
  ok: summary[:uploads_ok], sent: summary[:uploads_sent], seq: summary[:sequential_seconds].join('/'),
  mean: summary[:sequential_mean_seconds], par: summary[:parallel_wall_seconds],
  previews: summary[:previews_per_document].join(','), sig: summary[:preview_signatures].map { |s| s[0, 8] }.join(',')
)
