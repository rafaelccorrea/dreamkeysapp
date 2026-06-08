#!/usr/bin/env ruby
# Prepara bundle id, App Groups e perfil App Store da CheckInWidget no CI.
# Uso: ruby ios/scripts/codemagic_widget_signing_setup.rb /tmp/distribution_key.pem
#
# Pré-requisito manual (uma vez no portal Apple):
#   Identifiers → App Groups → group.com.dreamkeys.corretor

require 'json'
require 'open3'

CERT_KEY_PATH = ARGV[0] || '/tmp/distribution_key.pem'
BUNDLE_ID = ENV.fetch('BUNDLE_ID', 'com.dreamkeys.corretor')
WIDGET_BUNDLE = ENV.fetch('WIDGET_BUNDLE', "#{BUNDLE_ID}.CheckInWidget")
GROUP_ID = 'group.com.dreamkeys.corretor'

def run(*args, allow_fail: false)
  cmd = args.flatten.map(&:to_s)
  puts "+ #{cmd.join(' ')}"
  stdout, stderr, status = Open3.capture3(*cmd)
  puts stdout unless stdout.empty?
  warn stderr unless stderr.empty?
  abort(stderr.empty? ? "Comando falhou: #{cmd.join(' ')}" : stderr) if !status.success? && !allow_fail
  [stdout, stderr, status.success?]
end

def asc_json(*args)
  out, = run('app-store-connect', *args, '--json')
  JSON.parse(out)
rescue JSON::ParserError => e
  warn "[widget-ci] JSON inválido de app-store-connect #{args.first}: #{e.message}"
  nil
end

def bundle_resource_id(identifier)
  raw = asc_json('bundle-ids', 'list')
  return nil unless raw

  raw.fetch('data', []).each do |item|
    return item['id'] if item.dig('attributes', 'identifier') == identifier
  end
  nil
end

def ensure_bundle(identifier, name)
  rid = bundle_resource_id(identifier)
  if rid
    puts "[widget-ci] Bundle OK: #{identifier} (#{rid})"
    return rid
  end

  puts "[widget-ci] Criando bundle id #{identifier}…"
  run('app-store-connect', 'bundle-ids', 'create', identifier, '--name', name, '--platform', 'IOS')
  rid = bundle_resource_id(identifier)
  abort "[widget-ci] Não foi possível criar/encontrar #{identifier}" unless rid
  rid
end

def enable_app_groups(rid, label)
  puts "[widget-ci] Habilitando App Groups em #{label}…"
  run(
    'app-store-connect', 'bundle-ids', 'enable-capabilities', rid,
    '--capability', 'App Groups',
    allow_fail: true,
  )
end

def delete_portal_profiles(rid, label)
  raw = asc_json('bundle-ids', 'profiles', rid)
  return unless raw

  raw.fetch('data', []).each do |item|
    pid = item['id']
    name = item.dig('attributes', 'name') || pid
    next if pid.to_s.empty?

    puts "[widget-ci] Deletando perfil #{label}: #{name}"
    run('app-store-connect', 'profiles', 'delete', pid, allow_fail: true)
  end
end

def purge_local_widget_profiles
  dirs = [
    File.expand_path('~/Library/MobileDevice/Provisioning Profiles'),
    File.expand_path('~/Library/Developer/Xcode/UserData/Provisioning Profiles'),
    '/Users/builder/Library/MobileDevice/Provisioning Profiles',
  ]

  dirs.each do |dir|
    next unless Dir.exist?(dir)

    Dir.glob(File.join(dir, '*.mobileprovision')).each do |prov|
      meta = `security cms -D -i "#{prov}" 2>/dev/null`
      next unless meta.include?(WIDGET_BUNDLE)

      puts "[widget-ci] Removendo perfil local: #{File.basename(prov)}"
      File.delete(prov)
    end
  end
end

unless File.file?(CERT_KEY_PATH)
  abort "[widget-ci] Chave de distribuição não encontrada: #{CERT_KEY_PATH}"
end

main_rid = bundle_resource_id(BUNDLE_ID)
abort "[widget-ci] Bundle principal não encontrado: #{BUNDLE_ID}" unless main_rid

widget_rid = ensure_bundle(WIDGET_BUNDLE, 'CheckInWidget')

enable_app_groups(main_rid, BUNDLE_ID)
enable_app_groups(widget_rid, WIDGET_BUNDLE)

delete_portal_profiles(widget_rid, WIDGET_BUNDLE)
purge_local_widget_profiles

run(
  'app-store-connect', 'fetch-signing-files', WIDGET_BUNDLE,
  '--platform', 'IOS',
  '--type', 'IOS_APP_STORE',
  "--certificate-key=@file:#{CERT_KEY_PATH}",
  '--strict-match-identifier',
  '--delete-stale-profiles',
  '--create',
  '--verbose',
)

puts "[widget-ci] Widget signing preparado (#{WIDGET_BUNDLE}, #{GROUP_ID})."
