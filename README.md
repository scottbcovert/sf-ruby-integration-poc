# Salesforce & Ruby on Rails Integration Proof of Concept

This serves as a PoC to demonstrate how a Ruby on Rails app can be setup to integrate with the Salesforce REST API via the [OAuth2 JWT flow](https://help.salesforce.com/s/articleView?id=sf.remoteaccess_oauth_jwt_flow.htm&type=5)

## Getting Started

### Clone repo

`git clone https://github.com/scottbcovert/sf-ruby-integration-poc`

### Create a Private Key & Digital Cert

[Create a private key and self-signed digital certificate](https://developer.salesforce.com/docs/atlas.en-us.sfdx_dev.meta/sfdx_dev/sfdx_dev_auth_key_and_cert.htm) - take note that this guide creates a cert that will expire in one year, you may wish to change the `-days` parameter for a longer or shorter lived certificate

### Create a connected app

[Create a connected app](https://help.salesforce.com/articleView?id=connected_app_create.htm&type=5) in your Salesforce org

Select `Enable OAuth Settings` and set the OAuth scope for your connected app to include `api`, `refresh_token`, & `offline_access`

The callback URL is not used during the OAuth2 JWT flow, but it's required so you can just set it to `http://localhost:8080/callback`

On your connected app settings, select `Use digital signatures` and then upload the `server.crt` file created previously

### Config

Copy the contents of the `.env.sample` file into a local `.env` file, replacing the `SF_CLIENT_ID` and `SF_CLIENT_SECRET` values with your connected app's consumer key & secret

Set `SF_PRIVATE_KEY` to that of the private key matching the self-generated SSL cert associated with your connnected app. Note you will need to wrap the key in `"` and use `\n` characters as opposed to literal line breaks similar to the example in `.env.sample`

Run `ruby -e "require 'securerandom'; puts SecureRandom.hex(64)"` to generate a long random string for encrypting session cookies. Set `SECRET_KEY_BASE` to this value.

### Running locally

Run `ruby app.rb` from the root directory to start up the server

The app should be running at `localhost:8080`

### Running on Render

Go to the Render Dashboard and click `+ New > Web Service`

Connect your GitHub repository

Set the Start Command to `bundle exec ruby app.rb`

Select the `Free` instance type

Click `Deploy Web Service`

Click `Cancel deploy` since you still need to upload your `.env` file

Click `Environment`

Under `Secret Files` Click `+ Add > Upload files`

Select your `.env` file and then click `Save, rebuild, and deploy`

Update your Salesforce connnected app callback url(s) to include `https://sf-ruby-integration-poc.onrender.com/callback` based on the new url assigned by Render

The app should now be running on Render if you visit that same url in the browser

## Security

This project is meant as a PoC and leverages a connected app to interact with Salesforce APIs.

Connected apps are now being phased out in favor of their successor, external client apps.

The benefit of using a connected app with this PoC is that a Salesforce admin with the `Approve Uninstalled Connected Apps` permission can enable the integration without installing anything to their org beforehand.

That same admin could then officially 'install' the connected app to pre-approve other users based on their profile or an assigned permission set.

In production, using an external client app would offer better security.

Using an external client app would require an admin to first install a managed package containing a reference to it, admittedly adding friction to the onboarding process.

However, it would offer better security from the perspective of both the Salesforce admin and the integration maintainer.

The integration maintainer could easily rotate keys and update the digital cert associated with the external client app as needed without involving the Salesforce admin.

Using an external client app would also mean the JWT OAuth flow could be used exclusively without requiring the initial handshake be done through the web server with PKCE OAuth flow like this PoC requires.

This is beneficial from the Salesforce admin's perspective as no refresh token is *ever* displayed to an external server.

By having a reference to the external client app installed in their org the Salesforce admin also has more control over managing policies such as pre-approvals, IP restrictions, etc.

This zero trust model is a better long-term strategy for enterprise-ready Salesforce integrations.

## Resources

* [Guided walkthrough](https://www.youtube.com/watch?v=c5OZZsVkOKY)

## Built With

* [Ruby on Rails](https://github.com/rails/rails)
* [Restforce](https://github.com/restforce/restforce) - Ruby gem for interacting with Salesforce APIs

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details