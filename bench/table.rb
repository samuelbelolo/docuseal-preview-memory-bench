# frozen_string_literal: true

# Prints a Markdown table of every results/*/summary.json (or of the run directories given).
#
#   ruby table.rb [results/<label> ...]

require 'json'

dirs = ARGV.empty? ? Dir[File.join(__dir__, 'results', '*')].sort : ARGV

puts '| Run | Rest anon | memory.peak | Max anon | OOM killed | Uploads OK | Sequential uploads (s) | Mean (s) | ' \
     '2 at once (s) | Previews | Signature |'
puts '|---|---|---|---|---|---|---|---|---|---|---|'

dirs.each do |dir|
  file = File.join(dir, 'summary.json')
  next unless File.exist?(file)

  s = JSON.parse(File.read(file))
  previews = s['previews_per_document'].uniq.size == 1 ? "#{s['previews_per_document'].size} x #{s['previews_per_document'].first}" : s['previews_per_document'].join(',')

  puts "| #{s['label']} | #{s['rest_anon_mb']} | #{s['memory_peak_mb']} | #{s['max_anon_mb']} | " \
       "#{s['oom_killed'] ? 'yes' : 'no'} | #{s['uploads_ok']}/#{s['uploads_sent']} | " \
       "#{s['sequential_seconds'].join(' / ')} | #{s['sequential_mean_seconds']} | " \
       "#{s['parallel_wall_seconds'] || '-'} | #{previews} | #{s['preview_signatures'].map { |sig| sig[0, 8] }.join(',')} |"
end
