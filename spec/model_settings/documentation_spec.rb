# frozen_string_literal: true

require "spec_helper"

# rubocop:disable RSpecGuide/MinimumBehavioralCoverage
RSpec.describe ModelSettings::Documentation do
  after do
    ModelSettings.reset_configuration!
  end

  describe ".settings_documentation" do
    # Characteristic 1: Format
    context "when format is :markdown" do
      # Happy path: basic model with standard settings
      context "with basic model" do
        subject(:docs) { model_class.settings_documentation(format: :markdown) }

        let(:model_class) do
          Class.new(TestModel) do
            def self.name
              "DocumentationTestModel"
            end

            include ModelSettings::DSL

            setting :enabled,
              type: :column,
              description: "Enable main feature",
              default: false

            setting :api_key,
              type: :column,
              description: "API key for external service"
          end
        end

        it "includes model header" do
          expect(docs).to include("# DocumentationTestModel Settings")
        end

        it "includes generated timestamp" do
          expect(docs).to match(/Generated: \d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}/)
        end

        it "includes settings section header" do
          expect(docs).to include("## Settings")
        end

        it "includes setting name" do
          expect(docs).to include("### `enabled`")
        end

        it "includes setting description" do
          expect(docs).to include("Enable main feature")
        end

        it "includes setting type" do
          expect(docs).to include("| **Type** | column |")
        end

        it "includes storage information" do
          expect(docs).to include("| **Storage** | `enabled` column |")
        end

        it "includes default value" do
          expect(docs).to include("| **Default** | `false` |")
        end

        it "includes API methods section" do
          expect(docs).to include("**API Methods:**")
        end

        it "includes getter method" do
          expect(docs).to include("documentation_test_model.enabled")
        end

        it "includes setter method" do
          expect(docs).to include("documentation_test_model.enabled = value")
        end

        it "includes enable helper" do
          expect(docs).to include("documentation_test_model.enabled_enable!")
        end

        it "includes disable helper" do
          expect(docs).to include("documentation_test_model.enabled_disable!")
        end

        it "includes toggle helper" do
          expect(docs).to include("documentation_test_model.enabled_toggle!")
        end

        it "includes enabled query helper" do
          expect(docs).to include("documentation_test_model.enabled_enabled?")
        end

        it "includes disabled query helper" do
          expect(docs).to include("documentation_test_model.enabled_disabled?")
        end

        it "does NOT include deprecated marker" do
          expect(docs).not_to include("⚠️")
        end

        it "does NOT include authorization section" do
          expect(docs).not_to include("**Authorization**")
        end

        it "does NOT include dependencies section" do
          expect(docs).not_to include("**Dependencies:**")
        end
      end

      # Edge case: model with no settings
      context "with empty model" do
        subject(:docs) { model_class.settings_documentation(format: :markdown) }

        let(:model_class) do
          Class.new(TestModel) do
            def self.name
              "EmptyModel"
            end

            include ModelSettings::DSL
          end
        end

        it "shows no settings defined message" do
          expect(docs).to include("*No settings defined*")
        end

        it "does NOT include settings section header" do
          expect(docs).not_to include("## Settings")
        end
      end

      # Characteristic 2: Filter option
      context "with filter option" do
        let(:model_class) do
          Class.new(TestModel) do
            def self.name
              "FilterTestModel"
            end

            include ModelSettings::DSL

            setting :enabled,
              type: :column,
              description: "Active setting"

            setting :api_key,
              type: :column,
              description: "API key for service"

            setting :deprecated_feature,
              type: :column,
              deprecated: "Use :new_feature instead"
          end
        end

        context "without filter" do
          subject(:docs) { model_class.settings_documentation(format: :markdown) }

          it "includes all settings" do
            expect(docs).to include("### `enabled`")
            expect(docs).to include("### `api_key`")
            expect(docs).to include("### `deprecated_feature`")
          end
        end

        context "when filter is :active" do
          subject(:docs) { model_class.settings_documentation(format: :markdown, filter: :active) }

          it "includes non-deprecated settings" do
            expect(docs).to include("### `enabled`")
            expect(docs).to include("### `api_key`")
          end

          it "excludes deprecated settings" do
            expect(docs).not_to include("### `deprecated_feature`")
          end
        end

        context "when filter is :deprecated" do
          subject(:docs) { model_class.settings_documentation(format: :markdown, filter: :deprecated) }

          it "includes deprecated settings" do
            expect(docs).to include("### `deprecated_feature`")
          end

          it "excludes non-deprecated settings" do
            expect(docs).not_to include("### `enabled`")
            expect(docs).not_to include("### `api_key`")
          end
        end

        context "with custom proc filter" do
          subject(:docs) do
            model_class.settings_documentation(
              format: :markdown,
              filter: ->(setting) { setting.description&.include?("API") }
            )
          end

          it "includes settings matching custom condition" do
            expect(docs).to include("### `api_key`")
          end

          it "excludes settings not matching custom condition" do
            expect(docs).not_to include("### `enabled`")
            expect(docs).not_to include("### `deprecated_feature`")
          end
        end
      end

      # Characteristic 3: Deprecation
      context "with deprecated setting" do
        subject(:docs) { model_class.settings_documentation(format: :markdown) }

        let(:model_class) do
          Class.new(TestModel) do
            def self.name
              "DeprecatedModel"
            end

            include ModelSettings::DSL

            setting :deprecated_feature,
              type: :column,
              deprecated: "Use :new_feature instead"
          end
        end

        it "marks setting as deprecated" do
          expect(docs).to include("| **Deprecated** |")
        end

        it "includes deprecation warning emoji" do
          expect(docs).to include("⚠️")
        end

        it "includes deprecation message" do
          expect(docs).to include("Use :new_feature instead")
        end
      end

      # Characteristic 4: Authorization
      context "with authorization" do
        context "when model includes Roles module" do
          subject(:docs) { model_class.settings_documentation(format: :markdown) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "RolesDocModel"
              end

              include ModelSettings::DSL
              include ModelSettings::Modules::Roles

              setting :admin_feature,
                type: :column,
                viewable_by: [:admin],
                editable_by: [:admin, :manager]
            end
          end

          it "includes authorization section" do
            expect(docs).to include("| **Authorization** |")
          end

          it "includes viewable_by roles" do
            expect(docs).to include("View: :admin")
          end

          it "includes editable_by roles" do
            expect(docs).to include("Edit: :admin, :manager")
          end
        end

        context "when model includes Pundit module" do
          subject(:docs) { model_class.settings_documentation(format: :markdown) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "PunditDocModel"
              end

              include ModelSettings::DSL
              include ModelSettings::Modules::Pundit

              setting :billing,
                type: :column,
                authorize_with: :manage_billing?
            end
          end

          it "includes authorization section" do
            expect(docs).to include("| **Authorization** |")
          end

          it "includes required permission method" do
            expect(docs).to include("Requires `manage_billing?` permission")
          end
        end

        context "when model includes ActionPolicy module" do
          subject(:docs) { model_class.settings_documentation(format: :markdown) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "ActionPolicyDocModel"
              end

              include ModelSettings::DSL
              include ModelSettings::Modules::ActionPolicy

              setting :admin_panel,
                type: :column,
                authorize_with: :manage?
            end
          end

          it "includes authorization section" do
            expect(docs).to include("| **Authorization** |")
          end

          it "includes required permission method" do
            expect(docs).to include("Requires `manage?` permission")
          end
        end

        context "without authorization module" do
          subject(:docs) { model_class.settings_documentation(format: :markdown) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "NoAuthModel"
              end

              include ModelSettings::DSL

              setting :public_feature, type: :column
            end
          end

          it "does NOT include authorization section" do
            expect(docs).not_to include("**Authorization**")
          end
        end
      end

      # Characteristic 5: Dependencies
      context "with dependencies" do
        context "when setting has cascade" do
          subject(:docs) { model_class.settings_documentation(format: :markdown) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "CascadeDocModel"
              end

              include ModelSettings::DSL

              setting :parent,
                type: :column,
                cascade: {enable: true, disable: true} do
                setting :child, type: :column
              end
            end
          end

          it "includes dependencies section" do
            expect(docs).to include("**Dependencies:**")
          end

          it "includes cascade label" do
            expect(docs).to include("**Cascade**:")
          end

          it "includes cascade enable configuration" do
            expect(docs).to include("enable children")
          end

          it "includes cascade disable configuration" do
            expect(docs).to include("disable children")
          end
        end

        context "when setting has sync" do
          subject(:docs) { model_class.settings_documentation(format: :markdown) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "SyncDocModel"
              end

              include ModelSettings::DSL

              setting :feature_a,
                type: :column,
                sync: {mode: :forward, target: :feature_b}

              setting :feature_b, type: :column
            end
          end

          it "includes dependencies section" do
            expect(docs).to include("**Dependencies:**")
          end

          it "includes sync label" do
            expect(docs).to include("**Sync**:")
          end

          it "includes sync mode" do
            expect(docs).to include("forward")
          end

          it "includes sync target" do
            expect(docs).to include("feature_b")
          end
        end

        context "without dependencies" do
          subject(:docs) { model_class.settings_documentation(format: :markdown) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "NoDepsModel"
              end

              include ModelSettings::DSL

              setting :standalone, type: :column
            end
          end

          it "does NOT include dependencies section" do
            expect(docs).not_to include("**Dependencies:**")
          end
        end
      end
    end

    # Characteristic 1: Format = :json (mirror structure of :markdown)
    context "when format is :json" do
      context "with basic model" do
        subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

        let(:model_class) do
          Class.new(TestModel) do
            def self.name
              "DocumentationTestModel"
            end

            include ModelSettings::DSL

            setting :enabled,
              type: :column,
              description: "Enable main feature",
              default: false

            setting :api_key,
              type: :column,
              description: "API key for external service"
          end
        end

        it "includes model name" do
          expect(parsed["model"]).to eq("DocumentationTestModel")
        end

        it "includes generated timestamp" do
          expect(parsed["generated_at"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
        end

        it "includes settings array" do
          expect(parsed["settings"]).to be_an(Array)
        end

        it "includes correct number of settings" do
          expect(parsed["settings"].size).to eq(2)
        end

        it "includes setting name" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["name"]).to eq("enabled")
        end

        it "includes setting description" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["description"]).to eq("Enable main feature")
        end

        it "includes setting type" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["type"]).to eq("column")
        end

        it "includes storage information" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["storage"]).to eq({"type" => "column", "column" => "enabled"})
        end

        it "includes default value" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["default"]).to eq(false)
        end

        it "includes deprecated flag" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["deprecated"]).to eq(false)
        end

        it "includes API getter method" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["api"]["getter"]).to eq("documentation_test_model.enabled")
        end

        it "includes API setter method" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["api"]["setter"]).to eq("documentation_test_model.enabled = value")
        end

        it "includes API enable helper" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["api"]["enable"]).to eq("documentation_test_model.enabled_enable!")
        end

        it "includes API disable helper" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["api"]["disable"]).to eq("documentation_test_model.enabled_disable!")
        end

        it "includes API toggle helper" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["api"]["toggle"]).to eq("documentation_test_model.enabled_toggle!")
        end

        it "includes API enabled query helper" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["api"]["enabled?"]).to eq("documentation_test_model.enabled_enabled?")
        end

        it "includes API disabled query helper" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["api"]["disabled?"]).to eq("documentation_test_model.enabled_disabled?")
        end

        it "does NOT include authorization for settings without authorization" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["authorization"]).to be_nil
        end

        it "does NOT include dependencies for settings without dependencies" do
          enabled_setting = parsed["settings"].find { |s| s["name"] == "enabled" }
          expect(enabled_setting["dependencies"]).to be_nil
        end
      end

      context "with empty model" do
        subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

        let(:model_class) do
          Class.new(TestModel) do
            def self.name
              "EmptyModel"
            end

            include ModelSettings::DSL
          end
        end

        it "includes empty settings array" do
          expect(parsed["settings"]).to eq([])
        end
      end

      context "with filter option" do
        let(:model_class) do
          Class.new(TestModel) do
            def self.name
              "FilterTestModel"
            end

            include ModelSettings::DSL

            setting :enabled,
              type: :column,
              description: "Active setting"

            setting :api_key,
              type: :column,
              description: "API key for service"

            setting :deprecated_feature,
              type: :column,
              deprecated: "Use :new_feature instead"
          end
        end

        context "without filter" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

          it "includes all settings" do
            names = parsed["settings"].map { |s| s["name"] }
            expect(names).to match_array(["enabled", "api_key", "deprecated_feature"])
          end
        end

        context "when filter is :active" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json, filter: :active)) }

          it "includes non-deprecated settings" do
            names = parsed["settings"].map { |s| s["name"] }
            expect(names).to match_array(["enabled", "api_key"])
          end

          it "excludes deprecated settings" do
            names = parsed["settings"].map { |s| s["name"] }
            expect(names).not_to include("deprecated_feature")
          end
        end

        context "when filter is :deprecated" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json, filter: :deprecated)) }

          it "includes deprecated settings" do
            names = parsed["settings"].map { |s| s["name"] }
            expect(names).to eq(["deprecated_feature"])
          end

          it "excludes non-deprecated settings" do
            names = parsed["settings"].map { |s| s["name"] }
            expect(names).not_to include("enabled", "api_key")
          end
        end

        context "with custom proc filter" do
          subject(:parsed) do
            JSON.parse(
              model_class.settings_documentation(
                format: :json,
                filter: ->(setting) { setting.description&.include?("API") }
              )
            )
          end

          it "includes settings matching custom condition" do
            names = parsed["settings"].map { |s| s["name"] }
            expect(names).to eq(["api_key"])
          end

          it "excludes settings not matching custom condition" do
            names = parsed["settings"].map { |s| s["name"] }
            expect(names).not_to include("enabled", "deprecated_feature")
          end
        end
      end

      context "with deprecated setting" do
        subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

        let(:model_class) do
          Class.new(TestModel) do
            def self.name
              "DeprecatedModel"
            end

            include ModelSettings::DSL

            setting :deprecated_feature,
              type: :column,
              deprecated: "Use :new_feature instead"
          end
        end

        it "marks setting as deprecated" do
          deprecated_setting = parsed["settings"].first
          expect(deprecated_setting["deprecated"]).to eq("Use :new_feature instead")
        end
      end

      context "with authorization" do
        context "when model includes Roles module" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "RolesDocModel"
              end

              include ModelSettings::DSL
              include ModelSettings::Modules::Roles

              setting :admin_feature,
                type: :column,
                viewable_by: [:admin],
                editable_by: [:admin, :manager]
            end
          end

          it "includes authorization object" do
            admin_setting = parsed["settings"].first
            expect(admin_setting["authorization"]).to be_present
          end

          it "includes module name" do
            admin_setting = parsed["settings"].first
            expect(admin_setting["authorization"]["module"]).to eq("Roles")
          end

          it "includes viewable_by roles" do
            admin_setting = parsed["settings"].first
            expect(admin_setting["authorization"]["viewable_by"]).to eq(["admin"])
          end

          it "includes editable_by roles" do
            admin_setting = parsed["settings"].first
            expect(admin_setting["authorization"]["editable_by"]).to match_array(["admin", "manager"])
          end
        end

        context "when model includes Pundit module" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "PunditDocModel"
              end

              include ModelSettings::DSL
              include ModelSettings::Modules::Pundit

              setting :billing,
                type: :column,
                authorize_with: :manage_billing?
            end
          end

          it "includes authorization object" do
            billing_setting = parsed["settings"].first
            expect(billing_setting["authorization"]).to be_present
          end

          it "includes module name" do
            billing_setting = parsed["settings"].first
            expect(billing_setting["authorization"]["module"]).to eq("Pundit")
          end

          it "includes required permission method" do
            billing_setting = parsed["settings"].first
            expect(billing_setting["authorization"]["method"]).to eq("manage_billing?")
          end
        end

        context "when model includes ActionPolicy module" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "ActionPolicyDocModel"
              end

              include ModelSettings::DSL
              include ModelSettings::Modules::ActionPolicy

              setting :admin_panel,
                type: :column,
                authorize_with: :manage?
            end
          end

          it "includes authorization object" do
            admin_setting = parsed["settings"].first
            expect(admin_setting["authorization"]).to be_present
          end

          it "includes module name" do
            admin_setting = parsed["settings"].first
            expect(admin_setting["authorization"]["module"]).to eq("ActionPolicy")
          end

          it "includes required permission method" do
            admin_setting = parsed["settings"].first
            expect(admin_setting["authorization"]["method"]).to eq("manage?")
          end
        end

        context "without authorization module" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "NoAuthModel"
              end

              include ModelSettings::DSL

              setting :public_feature, type: :column
            end
          end

          it "does NOT include authorization object" do
            public_setting = parsed["settings"].first
            expect(public_setting["authorization"]).to be_nil
          end
        end
      end

      context "with dependencies" do
        context "when setting has cascade" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "CascadeDocModel"
              end

              include ModelSettings::DSL

              setting :parent,
                type: :column,
                cascade: {enable: true, disable: true} do
                setting :child, type: :column
              end
            end
          end

          it "includes dependencies object" do
            parent_setting = parsed["settings"].find { |s| s["name"] == "parent" }
            expect(parent_setting["dependencies"]).to be_present
          end

          it "includes cascade configuration" do
            parent_setting = parsed["settings"].find { |s| s["name"] == "parent" }
            expect(parent_setting["dependencies"]["cascade"]).to eq({"enable" => true, "disable" => true})
          end
        end

        context "when setting has sync" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "SyncDocModel"
              end

              include ModelSettings::DSL

              setting :feature_a,
                type: :column,
                sync: {mode: :forward, target: :feature_b}

              setting :feature_b, type: :column
            end
          end

          it "includes dependencies object" do
            sync_setting = parsed["settings"].find { |s| s["name"] == "feature_a" }
            expect(sync_setting["dependencies"]).to be_present
          end

          it "includes sync configuration" do
            sync_setting = parsed["settings"].find { |s| s["name"] == "feature_a" }
            expect(sync_setting["dependencies"]["sync"]).to eq({"mode" => "forward", "target" => "feature_b"})
          end
        end

        context "without dependencies" do
          subject(:parsed) { JSON.parse(model_class.settings_documentation(format: :json)) }

          let(:model_class) do
            Class.new(TestModel) do
              def self.name
                "NoDepsModel"
              end

              include ModelSettings::DSL

              setting :standalone, type: :column
            end
          end

          it "does NOT include dependencies object" do
            standalone_setting = parsed["settings"].first
            expect(standalone_setting["dependencies"]).to be_nil
          end
        end
      end
    end

    # Characteristic 1: Format = yaml
    context "when format is :yaml" do
      subject(:parsed) { YAML.safe_load(model_class.settings_documentation(format: :yaml)) }

      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "YamlTestModel"
          end

          include ModelSettings::DSL

          setting :enabled,
            type: :column,
            description: "Enable feature",
            default: false

          setting :api_key,
            type: :column,
            description: "API key"
        end
      end

      let(:enabled_setting) { parsed["settings"].find { |s| s["name"] == "enabled" } }

      it "includes model name" do
        expect(parsed["model"]).to eq("YamlTestModel")
      end

      it "includes generated timestamp" do
        expect(parsed["generated_at"]).to match(/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}/)
      end

      it "includes settings count" do
        expect(parsed["settings_count"]).to eq(2)
      end

      it "includes settings array" do
        expect(parsed["settings"]).to be_an(Array)
        expect(parsed["settings"].size).to eq(2)
      end

      it "includes setting name" do
        expect(enabled_setting["name"]).to eq("enabled")
      end

      it "includes setting description" do
        expect(enabled_setting["description"]).to eq("Enable feature")
      end

      it "includes setting type" do
        expect(enabled_setting["type"]).to eq("column")
      end

      it "includes default value" do
        expect(enabled_setting["default"]).to eq(false)
      end
    end

    # Characteristic 2: Format = html
    context "when format is :html" do
      subject(:html) { model_class.settings_documentation(format: :html) }

      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "HtmlTestModel"
          end

          include ModelSettings::DSL

          setting :enabled,
            type: :column,
            description: "Enable feature",
            default: false
        end
      end

      it "generates valid HTML" do
        expect(html).to include("<!DOCTYPE html>")
        expect(html).to include("<html")
        expect(html).to include("</html>")
      end

      it "includes model name in title" do
        expect(html).to include("<title>HtmlTestModel Settings Documentation</title>")
      end

      it "includes model name in heading" do
        expect(html).to include("<h1>HtmlTestModel Settings Documentation</h1>")
      end

      it "includes setting name" do
        expect(html).to include("<code>enabled</code>")
      end

      it "includes setting description" do
        expect(html).to include("Enable feature")
      end

      it "includes type badge" do
        expect(html).to include("badge-type")
        expect(html).to include("column")
      end

      it "includes properties table" do
        expect(html).to include("<table>")
        expect(html).to include("<th>Property</th>")
        expect(html).to include("<th>Value</th>")
      end

      it "includes API methods" do
        expect(html).to include("API Methods:")
        expect(html).to include("html_test_model.enabled")
        expect(html).to include("html_test_model.enabled_enable!")
      end

      context "with HTML characters in description" do
        let(:model_class) do
          Class.new(TestModel) do
            def self.name
              "TestModel"
            end

            include ModelSettings::DSL

            setting :test, type: :column, description: "<script>alert('xss')</script>"
          end
        end

        it "escapes HTML in content" do
          expect(html).to include("&lt;script&gt;")
          expect(html).not_to include("<script>alert")
        end
      end
    end

    # Characteristic 3: Format = unsupported
    context "when format is unsupported" do
      let(:model_class) do
        Class.new(TestModel) do
          def self.name
            "TestModel"
          end

          include ModelSettings::DSL

          setting :enabled, type: :column
        end
      end

      it "raises ArgumentError with descriptive message" do
        expect {
          model_class.settings_documentation(format: :xml)
        }.to raise_error(ArgumentError, /Unsupported documentation format/m)
      end
    end
  end
end
# rubocop:enable RSpecGuide/MinimumBehavioralCoverage
