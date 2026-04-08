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

    post family_imports_path, params: { family_import: { replace_rules: "0", import_scope: "rules" } }
    assert_redirected_to root_path

    get new_family_import_path(scope: "categories")
    assert_redirected_to root_path
  end

  test "non-admin can view family import history frame" do
    sign_in @non_admin

    get family_imports_path
    assert_response :success
  end

  test "admin can create import and job completes" do
    temp = Tempfile.new([ "export", ".zip" ])
    temp.binmode
    temp.write(Family::DataExporter.new(@family).generate_export.read)
    temp.rewind
    file = Rack::Test::UploadedFile.new(temp.path, "application/zip")

    assert_enqueued_with(job: FamilyDataImportJob) do
      post family_imports_path, params: { family_import: { import_file: file, replace_rules: "0", import_scope: "rules" } }
    end

    assert_redirected_to imports_path
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
    FamilyImport.new(family: @family, status: :completed, replace_rules: false, import_scope: "rules").tap { |r| r.save(validate: false) }

    get family_imports_path
    assert_response :success
    assert_match "Done", response.body
  end

  test "admin can open categories import modal" do
    get new_family_import_path(scope: "categories")
    assert_response :success
    assert_select "h2", text: "Import categories"
  end

  test "admin can open rules import modal" do
    get new_family_import_path(scope: "rules")
    assert_response :success
    assert_select "h2", text: "Import rules"
  end

  test "admin can open full export import modal" do
    get new_family_import_path(scope: "full")
    assert_response :success
    assert_select "h2", text: "Import full export (zip)"
  end

  test "invalid scope redirects to new import" do
    get new_family_import_path(scope: "nope")
    assert_redirected_to new_import_path
  end
end
