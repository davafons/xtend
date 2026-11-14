# The browser extension as a zip of this app's extension/ folder, to unzip and load unpacked.
class ExtensionsController < ApplicationController
  FILES = %w[*.js *.json *.html *.css icons/*.png README.md].freeze

  def show
    root = Rails.root.join("extension")
    zip = Zip::OutputStream.write_buffer do |out|
      FILES.flat_map { Dir.glob(root.join(_1)) }.sort.each do |path|
        out.put_next_entry("xtend-extension/#{Pathname(path).relative_path_from(root)}")
        out.write(File.binread(path))
      end
    end
    send_data zip.string, filename: "xtend-extension.zip", type: "application/zip"
  end
end
