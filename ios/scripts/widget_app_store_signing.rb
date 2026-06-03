#!/usr/bin/env ruby
# Verifica / aplica perfil App Store da CheckInWidget (com App Groups) no Xcode.
# Uso no Codemagic:
#   ruby ios/scripts/widget_app_store_signing.rb verify
#   ruby ios/scripts/widget_app_store_signing.rb apply

require 'xcodeproj'

WIDGET_BUNDLE = ENV.fetch('WIDGET_BUNDLE', 'com.dreamkeys.corretor.CheckInWidget')
GROUP_ID = 'group.com.dreamkeys.corretor'
PROJECT_PATH = File.expand_path('../Runner.xcodeproj', __dir__)

def profile_dirs
  [
    File.expand_path('~/Library/MobileDevice/Provisioning Profiles'),
    File.expand_path('~/Library/Developer/Xcode/UserData/Provisioning Profiles'),
  ]
end

def decode_provision(path)
  tmp = File.join(Dir.tmpdir, "cm_prov_#{Process.pid}.plist")
  ok = system('security', 'cms', '-D', '-i', path, '-o', tmp, %i[out err] => File::NULL)
  return nil unless ok && File.exist?(tmp)

  Xcodeproj::Plist.read_from_path(tmp)
ensure
  File.delete(tmp) if tmp && File.exist?(tmp)
end

def widget_profile_valid?(plist)
  return false unless plist.is_a?(Hash)

  ent = plist['Entitlements'] || {}
  app_id = ent['application-identifier'].to_s
  return false unless app_id.end_with?(".#{WIDGET_BUNDLE}")

  groups = ent['com.apple.security.application-groups']
  Array(groups).include?(GROUP_ID)
end

def find_widget_profile
  profile_dirs.each do |dir|
    next unless Dir.exist?(dir)

    Dir.glob(File.join(dir, '*.mobileprovision')).each do |path|
      plist = decode_provision(path)
      next unless widget_profile_valid?(plist)

      return { path: path, plist: plist }
    end
  end
  nil
end

def team_id_from(plist)
  ent = plist['Entitlements'] || {}
  ent['com.apple.developer.team-identifier'] ||
    Array(plist['TeamIdentifier']).first ||
    Array(plist['TeamIdentifier']).join
end

mode = ARGV.fetch(0, 'verify')

case mode
when 'verify'
  hit = find_widget_profile
  unless hit
    warn "[widget-signing] Nenhum .mobileprovision App Store para #{WIDGET_BUNDLE} com #{GROUP_ID}."
    exit 1
  end
  puts "[widget-signing] OK: #{File.basename(hit[:path])} (#{hit[:plist]['Name']})"
  exit 0

when 'apply'
  hit = find_widget_profile
  unless hit
    warn "[widget-signing] apply: perfil da widget não encontrado."
    exit 1
  end

  name = hit[:plist]['Name']
  team = team_id_from(hit[:plist])
  project = Xcodeproj::Project.open(PROJECT_PATH)
  widget = project.targets.find { |t| t.name == 'CheckInWidget' }
  unless widget
    warn '[widget-signing] Target CheckInWidget não encontrado.'
    exit 1
  end

  %w[Release Profile].each do |config_name|
    config = widget.build_configurations.find { |c| c.name == config_name }
    next unless config

    bs = config.build_settings
    bs['CODE_SIGN_STYLE'] = 'Manual'
    bs['DEVELOPMENT_TEAM'] = team if team && !team.empty?
    bs['CODE_SIGN_IDENTITY'] = 'Apple Distribution'
    bs['CODE_SIGN_IDENTITY[sdk=iphoneos*]'] = 'Apple Distribution'
    bs['PROVISIONING_PROFILE_SPECIFIER'] = name
  end

  project.save
  puts "[widget-signing] Aplicado em CheckInWidget (Release/Profile): #{name} / team #{team}"
  exit 0

else
  warn "Uso: #{$PROGRAM_NAME} verify|apply"
  exit 2
end
