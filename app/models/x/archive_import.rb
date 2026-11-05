# Reads DM metadata from a downloaded X archive zip. Only the manifest, account, and DM files are opened;
# message text is never read into storage and encrypted chat contents stay encrypted.
class X::ArchiveImport < ApplicationRecord
  include WorkspaceScoped
  self.table_name = "archive_imports"
  class Invalid < StandardError; end
  MAX_ENTRY_BYTES = 200.megabytes
  FILE_NAME = %r{\Adata/[a-z0-9-]+\.js\z}

  validates :owner_x_id, :generated_at, :account_created_at, presence: true

  def self.import!(path)
    owner = Current.workspace.owner_x_id
    raise Invalid, "Connect your X account first so the archive can be matched to it." if owner.blank?
    Zip::File.open(path) do |zip|
      manifest = read(zip, "data/manifest.js")
      account = manifest_files(manifest, "account").flat_map { |name| read(zip, name) }.first&.fetch("account")
      raise Invalid, "This archive has no account file." unless account
      raise Invalid, "This archive belongs to a different X account. Nothing was imported." unless account.fetch("accountId") == owner
      transaction do
        counts = Hash.new(0)
        manifest_files(manifest, "directMessages").each do |name|
          read(zip, name).each do |item|
            conversation = item.fetch("dmConversation")
            participants = conversation.fetch("conversationId").split("-")
            conversation.fetch("messages").each do |message|
              data = message["messageCreate"] or next
              counts[DirectMessage.record!(x_id: data.fetch("id"), conversation_x_id: conversation.fetch("conversationId"), participants: participants,
                sender_x_id: data.fetch("senderId"), occurred_at: Time.iso8601(data.fetch("createdAt")), source: "archive")] += 1
            end
          end
        end
        manifest_files(manifest, "messageEvent").each do |name|
          read(zip, name).each do |item|
            event = item.fetch("messageEvent")
            next unless event.fetch("detail").key?("messageCreateEvent")
            counts[DirectMessage.record!(x_id: event.fetch("messageId"), conversation_x_id: event.fetch("conversationId"),
              participants: event.fetch("conversationId").split(":"), sender_x_id: event.fetch("senderId"),
              occurred_at: Time.at(Integer(event.fetch("createdAtMsec")) / 1000r), source: "archive")] += 1
          end
        end
        info = manifest.fetch("archiveInfo")
        create!(owner_x_id: owner, generated_at: Time.iso8601(info.fetch("generationDate")), account_created_at: Time.iso8601(account.fetch("createdAt")),
          partial: info["isPartialArchive"] != false, direct_messages_count: counts[:new], skipped_count: counts[:skipped])
      end
    end
  rescue Zip::Error
    raise Invalid, "Choose the .zip file X sent you."
  rescue JSON::ParserError, KeyError, ArgumentError, TypeError, NoMethodError, ActiveRecord::RecordInvalid
    raise Invalid, "The archive could not be read. Nothing was imported."
  end

  def self.manifest_files(manifest, type)
    Array(manifest.dig("dataTypes", type, "files")).map { |file| file.fetch("fileName") }.each do |name|
      raise Invalid, "The archive manifest lists an unexpected file." unless name.match?(FILE_NAME)
    end
  end

  def self.read(zip, name)
    entry = zip.find_entry(name) or raise Invalid, "The archive is missing #{name}."
    raise Invalid, "#{name} is too large to import." if entry.size > MAX_ENTRY_BYTES
    text = entry.get_input_stream.read(MAX_ENTRY_BYTES + 1)
    raise Invalid, "#{name} is too large to import." if text.bytesize > MAX_ENTRY_BYTES
    JSON.parse(text.sub(/\A\s*window\.[\w.]+\s*=\s*/, "").sub(/;\s*\z/, ""))
  end
  private_class_method :manifest_files, :read
end
