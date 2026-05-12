
# /home/ubuntu/fix_podfile.rb

require 'xcodeproj'

# Caminho para o Podfile
podfile_path = File.join(Dir.pwd, 'ios', 'Podfile')

# Verifica se o Podfile existe
unless File.exist?(podfile_path)
  puts "Erro: Podfile não encontrado em #{podfile_path}"
  exit 1
end

puts "Lendo Podfile em #{podfile_path}"

# Lê o conteúdo do Podfile
podfile_content = File.read(podfile_path)

# Garante que a plataforma iOS seja 15.0
# Se a linha 'platform :ios' existir, substitui. Caso contrário, adiciona no início.
if podfile_content =~ /^platform :ios, ['"].*?['"]/
  podfile_content.gsub!(/^platform :ios, ['"].*?['"]/, "platform :ios, '15.0'")
  puts "Plataforma iOS atualizada para 15.0 no Podfile."
else
  podfile_content = "platform :ios, '15.0'\n" + podfile_content
  puts "Plataforma iOS 15.0 adicionada ao Podfile."
end

# Injeta a configuração do IPHONEOS_DEPLOYMENT_TARGET no bloco post_install existente.
# Isso é crucial para resolver conflitos de dependência do Firebase e evitar múltiplos hooks.
# Verifica se a configuração já existe para evitar duplicação.

# Primeiro, remove qualquer injeção anterior para evitar duplicação
podfile_content.gsub!(/\n\s*target\.build_configurations\.each do \|config\|\n\s*config\.build_settings\['IPHONEOS_DEPLOYMENT_TARGET'\] = ['"].*?['"]\n\s*end/, '')

# Encontra o bloco post_install que contém flutter_additional_ios_build_settings
if podfile_content =~ /post_install do \|installer\|.*?flutter_additional_ios_build_settings\(installer\.pods_project\)/m
  unless podfile_content =~ /config\.build_settings\['IPHONEOS_DEPLOYMENT_TARGET'\] = ['"]15\.0['"]/
    podfile_content.gsub!(/(flutter_additional_ios_build_settings\(installer\.pods_project\))/) do |match|
      "#{match}\n    installer.pods_project.targets.each do |target|\n      target.build_configurations.each do |config|\n        config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'\n      end\n    end"
    end
    puts "IPHONEOS_DEPLOYMENT_TARGET = '15.0' injetado no bloco post_install."
  else
    puts "IPHONEOS_DEPLOYMENT_TARGET já configurado para 15.0 no bloco post_install. Pulando injeção."
  end
else
  puts "Aviso: Bloco post_install com flutter_additional_ios_build_settings não encontrado. Injeção manual pode ser necessária."
end

# Escreve o Podfile modificado de volta
File.write(podfile_path, podfile_content)
puts "Podfile modificado e salvo com sucesso."

# Opcional: Para garantir que o Xcode Project também reflita a mudança
# Isso é mais complexo e geralmente o pod install já faz isso, mas é um fallback
# begin
#   project_path = Dir.glob(File.join(Dir.pwd, 'ios', '*.xcodeproj')).first
#   if project_path
#     project = Xcodeproj::Project.open(project_path)
#     project.targets.each do |target|
#       target.build_configurations.each do |config|
#         config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
#       end
#     end
#     project.save
#     puts "Xcode project #{project_path} atualizado com deployment target 15.0."
#   else
#     puts "Aviso: Arquivo .xcodeproj não encontrado para atualização direta."
#   end
# rescue => e
#   puts "Erro ao tentar atualizar o arquivo .xcodeproj: #{e.message}"
# end
