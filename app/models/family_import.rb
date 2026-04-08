class FamilyImport < ApplicationRecord
  IMPORT_SCOPES = %w[full categories rules monthly_planning].freeze

  belongs_to :family

  has_one_attached :import_file

  enum :status, {
    pending: "pending",
    processing: "processing",
    completed: "completed",
    failed: "failed"
  }, default: :pending, validate: true

  scope :ordered, -> { order(created_at: :desc) }

  validates :import_scope, presence: true, inclusion: { in: IMPORT_SCOPES }

  validate :import_file_attached, on: :create
  validate :import_file_size, on: :create

  private

    def import_file_attached
      errors.add(:import_file, "must be selected") unless import_file.attached?
    end

    def import_file_size
      return unless import_file.attached?

      if import_file.byte_size > 50.megabytes
        errors.add(:import_file, "is too large (max 50MB)")
      end
    end
end
