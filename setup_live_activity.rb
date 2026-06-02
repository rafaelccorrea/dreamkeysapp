# setup_live_activity.rb
#
# Cria/garante a Widget Extension da Live Activity (Ilha Dinâmica do check-in)
# no Runner.xcodeproj — programaticamente, via gem `xcodeproj` (a mesma já usada
# por fix_podfile.rb). Roda no Codemagic ANTES do `pod install`.
#
# Princípios:
#   * SÓ age quando ENABLE_LIVE_ACTIVITY=true. Sem o flag, é um no-op total e o
#     build fica idêntico ao de hoje.
#   * Idempotente: pode rodar várias vezes; não duplica target/fases.
#   * À prova de falha: qualquer erro é logado e o script termina com exit 0,
#     deixando o projeto utilizável — o build NUNCA quebra por causa daqui
#     (no pior caso, a feature só não é incluída).
#
# Pré-requisitos no portal Apple (uma vez, feitos pelo dono da conta):
#   1. App Group `group.com.dreamkeys.corretor` criado.
#   2. Capability "App Groups" habilitada nos bundle ids
#      `com.dreamkeys.corretor` e `com.dreamkeys.corretor.CheckInWidget`.

ENABLE = %w[1 true yes on].include?((ENV['ENABLE_LIVE_ACTIVITY'] || '').strip.downcase)

unless ENABLE
  puts '[live-activity] ENABLE_LIVE_ACTIVITY não definido — pulando (build inalterado).'
  exit 0
end

begin
  require 'xcodeproj'

  APP_BUNDLE_ID = (ENV['BUNDLE_ID'] && !ENV['BUNDLE_ID'].empty?) ? ENV['BUNDLE_ID'] : 'com.dreamkeys.corretor'
  WIDGET_NAME   = 'CheckInWidget'
  WIDGET_BUNDLE_ID = "#{APP_BUNDLE_ID}.#{WIDGET_NAME}"
  GROUP_ID      = 'group.com.dreamkeys.corretor'
  DEPLOYMENT    = '16.1'

  project_path = Dir.glob(File.join(Dir.pwd, 'ios', '*.xcodeproj')).first
  raise "Runner.xcodeproj não encontrado em ios/" unless project_path

  project = Xcodeproj::Project.open(project_path)

  runner = project.targets.find { |t| t.name == 'Runner' }
  raise 'Target Runner não encontrado' unless runner

  # ── 1. Target da extension (cria só se não existir) ───────────────────────
  widget = project.targets.find { |t| t.name == WIDGET_NAME }
  if widget
    puts "[live-activity] Target #{WIDGET_NAME} já existe — garantindo configs."
  else
    puts "[live-activity] Criando target #{WIDGET_NAME}…"
    widget = project.new_target(:app_extension, WIDGET_NAME, :ios, DEPLOYMENT, nil, :swift)
  end

  # ── 2. Grupo + arquivos-fonte ─────────────────────────────────────────────
  group = project.main_group.find_subpath(WIDGET_NAME, true)
  group.set_source_tree('SOURCE_ROOT')
  group.set_path(WIDGET_NAME)

  add_ref = lambda do |filename|
    existing = group.files.find { |f| f.display_name == filename }
    existing || group.new_reference(filename)
  end

  swift_files = %w[CheckInLiveActivity.swift CheckInWidgetBundle.swift]
  swift_refs = swift_files.map { |f| add_ref.call(f) }

  # Garante que os .swift estejam na fase de compilação (sem duplicar).
  source_paths = widget.source_build_phase.files_references.map(&:display_name)
  swift_refs.each do |ref|
    widget.source_build_phase.add_file_reference(ref) unless source_paths.include?(ref.display_name)
  end

  info_ref = add_ref.call('Info.plist')
  add_ref.call('CheckInWidget.entitlements')

  # ── 3. Frameworks de sistema ──────────────────────────────────────────────
  begin
    have = widget.frameworks_build_phase.files_references.map(&:display_name)
    %w[WidgetKit.framework SwiftUI.framework ActivityKit.framework].each do |fw|
      widget.add_system_framework(fw.sub('.framework', '')) unless have.include?(fw)
    end
  rescue => e
    puts "[live-activity] aviso ao adicionar frameworks: #{e.message}"
  end

  # ── 4. Build settings (todas as configs) ──────────────────────────────────
  # base = Generated.xcconfig → resolve FLUTTER_BUILD_NAME/NUMBER (CFBundle*).
  generated = project.files.find { |f| f.path && f.path.end_with?('Generated.xcconfig') }

  # Garante uma config Profile espelhando Release (Runner tem Debug/Release/Profile).
  unless widget.build_configurations.any? { |c| c.name == 'Profile' }
    widget.add_build_configuration('Profile', :release)
  end

  widget.build_configurations.each do |config|
    config.base_configuration_reference = generated if generated
    bs = config.build_settings
    bs['PRODUCT_BUNDLE_IDENTIFIER'] = WIDGET_BUNDLE_ID
    bs['PRODUCT_NAME'] = '$(TARGET_NAME)'
    bs['INFOPLIST_FILE'] = "#{WIDGET_NAME}/Info.plist"
    bs['CODE_SIGN_ENTITLEMENTS'] = "#{WIDGET_NAME}/#{WIDGET_NAME}.entitlements"
    bs['IPHONEOS_DEPLOYMENT_TARGET'] = DEPLOYMENT
    bs['SWIFT_VERSION'] = '5.0'
    bs['TARGETED_DEVICE_FAMILY'] = '1,2'
    bs['GENERATE_INFOPLIST_FILE'] = 'NO'
    bs['SKIP_INSTALL'] = 'NO'
    bs['CLANG_ENABLE_MODULES'] = 'YES'
    bs['ENABLE_BITCODE'] = 'NO'
    bs['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
    bs['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
    bs['LD_RUNPATH_SEARCH_PATHS'] = [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@executable_path/../../Frameworks',
    ]
  end
  info_ref # referenciado só p/ manter o arquivo visível no grupo

  # ── 5. Dependência + embed da .appex no Runner ────────────────────────────
  runner.add_dependency(widget) unless runner.dependencies.any? { |d| d.target == widget }

  embed = runner.copy_files_build_phases.find { |p| p.name == 'Embed Foundation Extensions' }
  unless embed
    embed = runner.new_copy_files_build_phase('Embed Foundation Extensions')
    embed.symbol_dst_subfolder_spec = :plug_ins
  end
  unless embed.files_references.include?(widget.product_reference)
    bf = embed.add_file_reference(widget.product_reference, true)
    bf.settings = { 'ATTRIBUTES' => ['RemoveHeadersOnCopy'] }
  end

  # ── 6. Ordena o embed ANTES do "Thin Binary" (evita "Cycle inside Runner") ─
  begin
    phases = runner.build_phases
    phases.delete(embed)
    thin_index = phases.find_index { |p| p.respond_to?(:display_name) && p.display_name == 'Thin Binary' } || phases.length
    phases.insert(thin_index, embed)
  rescue => e
    puts "[live-activity] aviso ao reordenar fases: #{e.message}"
  end

  # ── 7. App Group nas entitlements do Runner ───────────────────────────────
  begin
    ent_path = File.join(Dir.pwd, 'ios', 'Runner', 'Runner.entitlements')
    ent = (File.exist?(ent_path) ? Xcodeproj::Plist.read_from_path(ent_path) : nil) || {}
    groups = ent['com.apple.security.application-groups'] || []
    unless groups.include?(GROUP_ID)
      groups << GROUP_ID
      ent['com.apple.security.application-groups'] = groups
      Xcodeproj::Plist.write_to_path(ent, ent_path)
      puts "[live-activity] App Group adicionado ao Runner.entitlements."
    end
  rescue => e
    puts "[live-activity] aviso ao editar Runner.entitlements: #{e.message}"
  end

  project.save
  puts "[live-activity] OK — target #{WIDGET_NAME} (#{WIDGET_BUNDLE_ID}) integrado."
rescue => e
  puts '=================================================================='
  puts "[live-activity] FALHA ao integrar a extension: #{e.class}: #{e.message}"
  puts e.backtrace.first(5).join("\n")
  puts '[live-activity] Seguindo SEM a Live Activity — o build não será abortado.'
  puts '=================================================================='
  exit 0
end
