module Houdini
	module Nonprofit
		class CreateCommand < Rails::Command::Base
			desc "Create a new nonprofit on your Houdini instance"
			option :super_admin, aliases: '-su', default: false, type: :boolean, desc: "Make the nonprofit admin a super user (they can access any nonprofit's dashboards)"
			option :confirm_admin, default: true, type: :boolean, desc: "Require the nonprofit admin to be confirmed via email"

			option :nonprofit_name, default: nil, desc: "Provide the nonprofit's name"
			option :state_code, default: nil, desc: "Provide the nonprofit' state code"
			option :city, default: nil, desc: "Provide the nonprofit's city"
			option :nonprofit_website, default: nil, desc: "[OPTIONAL] Provide the nonprofit public website"
			option :nonprofit_email, default: nil, desc: "[OPTIONAL] Provide the nonprofit public email"
			option :nonprofit_phone, default: nil, desc: "[OPTIONAL] Provide the nonprofit's admin's phone"

			option :user_name, default: nil, desc: "Provide the nonprofit's admin's name"
			option :user_email, default: nil, desc: "Provide the nonprofit's admin's email address (It'll be used for logging in)"
			option :user_password, default: nil, desc: "Provide the nonprofit's admin's password"

			def perform
				result = {
					nonprofit: {
						name: options[:nonprofit_name] || ask("What is the nonprofit's name?"),
						state_code: options[:state_code] || ask("What is the nonprofit's state?"),
						city: options[:city] || ask("What is the nonprofit's city?"),
						website: options[:nonprofit_website] || ask("[OPTIONAL] What is the nonprofit's public website?"),
						email: options[:nonprofit_email] || ask("[OPTIONAL] What is the nonprofit's public e-mail?"),
						phone: options[:nonprofit_phone] || ask("[OPTIONAL] What is your nonprofit's public phone number?")
					}, 
					user: {
						name: options[:user_name] || ask("What is your nonprofit's admin's name?"),
						email: options[:user_email] || ask("What is your nonprofit's admin's email address? (It'll be used for logging in)"),
						password: options[:user_password] || ask("What is the nonprofit's admin's password?", echo: false)
					}
				}
				say
				require_application_and_environment!

				creation_result = Houdini::NonprofitCreation.new(result, options).call

				creation_result[:messages].each do |msg|
					say(msg)
				end
			end
		end
	end
end