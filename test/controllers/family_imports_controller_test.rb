require "test_helper"
require "tempfile"

class FamilyImportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = users(:family_admin)
    @non_admin = users(:family_member)
    @family = @admin.family

    sign_in @admin
  end

  test "non-admin cannot import" do
    sign_in @non_admin

    post family_imports_path, params: { family_import: { replace_rules: "0" } }
    assert_redirected_to root_path

    get family_imports_path
    assert_redirected_to root_path
  end

  test "admin can create import and job completes" do
    temp = Tempfile.new([ "export", ".zip" ])
    temp.binmode
    temp.write(Family::DataExporter.new(@family).generate_export.read)
    temp.rewind
    file = Rack::Test::UploadedFile.new(temp.path, "application/zip")

    assert_enqueued_with(job: FamilyDataImportJob) do
      post family_imports_path, params: { family_import: { import_file: file, replace_rules: "0" } }
    end

    assert_redirected_to settings_profile_path
    assert_match(/Import started/, flash[:notice])

    import = @family.family_imports.last
    assert_equal "pending", import.status

    perform_enqueued_jobs
    import.reload
    assert_equal "completed", import.status
  ensure
    temp&.close!
  end

  test "admin can view import list" do
    FamilyImport.new(family: @family, status: :completed, replace_rules: false).tap { |r| r.save(validate: false) }

    get family_imports_path
    assert_response :success
    assert_match "Done", response.body
  end
end
