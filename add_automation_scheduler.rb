#!/usr/bin/env ruby

require 'xcodeproj'

project_path = 'CryptoSavingsTracker.xcodeproj'
project = Xcodeproj::Project.open(project_path)

target = project.targets.find { |t| t.name == 'CryptoSavingsTracker' }
unless target
  puts "❌ Target 'CryptoSavingsTracker' not found"
  exit 1
end

# Add AutomationScheduler.swift
file_path = 'CryptoSavingsTracker/Services/AutomationScheduler.swift'
group = project['CryptoSavingsTracker/Services']

unless group
  puts "❌ Services group not found"
  exit 1
end

# Check if file already exists in project
existing_ref = group.files.find { |f| f.path == 'AutomationScheduler.swift' }

if existing_ref
  puts "✅ AutomationScheduler.swift already in project"
else
  file_ref = group.new_reference('AutomationScheduler.swift')
  file_ref.source_tree = '<group>'
  target.source_build_phase.add_file_reference(file_ref)
  puts "✅ Added AutomationScheduler.swift to project"
end

project.save
puts "✅ Project saved"
