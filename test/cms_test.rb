ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../cms.rb"


class AppTest < Minitest::Test
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_root)
    create_document "about.md", "#Ruby is simple in appearance, but is very complex inside"
    create_document "another_document.txt"
    create_document "changes.txt", "This site is dedicated to history of Ruby language evolution. Basically, it is just the same information that each Ruby versionâ€™s NEWS file contains, just in more readable and informative manner."
  end

  def teardown
    delete_user if @last_request
    delete_credentials('testuser')
    FileUtils.rm_rf(data_root)
  end

  def sign_in(user='admin', pass='secret')
    post "/users/signin", username: user, password: pass
  end
  
  def sign_out
    get '/users/signout'
  end
  
  def session
    last_request.env["rack.session"]
  end

  def delete_user
    session.delete(:username)
  end

  def admin_session
    { "rack.session" => { username: 'admin'} }
  end

  def get_as_admin(route)
    get route, {}, admin_session
  end

  def post_as_admin(route, **params)
    post route, params, admin_session
  end

  def test_sign_in_page
    get '/users/signin'

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'action="/users/signin" method="post"'
    assert_includes last_response.body, 'label for="username">Username'
    assert_includes last_response.body, 'label for="password">Password'
    assert_includes last_response.body, 'type="submit" value="Sign In"'
  end

  def test_sign_in
    sign_in('admin', 'secret')

    assert_equal 302, last_response.status
    assert_equal 'Welcome!', session[:message]

    get last_response['Location']

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'about.md'
  end

  def test_sign_in_invalid_credentials
    sign_in('invalid', 'password')

    assert_equal 422, last_response.status
    assert_includes last_response.body, 'Invalid credentials.'
    assert_includes last_response.body, 'action="/users/signin" method="post"'
    assert_includes last_response.body, 'label for="username">Username'
    assert_includes last_response.body, 'label for="password">Password'
    assert_includes last_response.body, 'type="submit" value="Sign In"'
  end

  def test_sign_out
    sign_out

    assert_equal 302, last_response.status
    assert_equal 'You have been signed out.', session[:message]

    get last_response["Location"]

    assert_includes last_response.body, 'action="/users/signin"'
  end

  def test_index_signed_out
    get "/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, 'action="/users/signin"'
    refute_includes last_response.body, 'about.md'
  end

  def test_index # test for listing of documents, edit links, new document
    get_as_admin "/"

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/html"
    assert_includes last_response.body, "about.md"
    assert_includes last_response.body, "changes.txt"
    assert_includes last_response.body, 'action="about.md/edit'
    assert_includes last_response.body, '<a href="/new_doc/">'
    assert_includes last_response.body, 'action="about.md/delete"'
    assert_includes last_response.body, 'Signed in as admin'
    assert_includes last_response.body, 'action="/users/signout"'
    assert_includes last_response.body, 'Sign Out</button>'
  end
 
  def test_content # test to see if content can be accessed
    get_as_admin '/changes.txt'

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/plain"
    assert_includes last_response.body, "This site is dedicated to history of Ruby language"
  end

  def test_nonexistant_content # test for redirection, error message, clearing of error message
    get_as_admin '/thisfiledoesnotexist.txt'

    assert_equal 302, last_response.status
    assert_equal "thisfiledoesnotexist.txt does not exist.", session[:message]

    get last_response["Location"]

    assert_equal 200, last_response.status

    get "/"
    refute_includes last_response.body, "thisfiledoesnotexist.txt does not exist."
  end

  def test_markdown_to_html_content # test for content conversion from markdown to HTML
    get_as_admin '/about.md'

    assert_equal 200, last_response.status
    assert_includes last_response["Content-Type"], "text/html"
    assert_includes last_response.body, "<h1>Ruby is"
  end

  def test_content_edit_page # test contents of edit page
    get_as_admin '/changes.txt/edit'

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Rename changes.txt"
    assert_includes last_response.body, "Edit content of changes.txt:"
    assert_includes last_response.body, "<textarea"
    assert_includes last_response.body, 'type="submit"'
  end

  def test_content_edit_page_nonexistant_content
    get_as_admin '/thisfiledoesnotexist.txt/edit'

    assert_equal 302, last_response.status
    assert_equal "thisfiledoesnotexist.txt does not exist.", session[:message]
    
    get last_response["Location"]

    assert_equal 200, last_response.status

    get "/"
    refute_includes last_response.body, "thisfiledoesnotexist.txt does not exist."
  end

  def test_content_edit_page_signed_out
    get 'about.md'

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]
  end

  def test_content_edit_update
    new_content = "THIS IS A NEW EDIT VIA TESTING - #{Time.now.getutc}"

    post_as_admin "/changes.txt/edit", updated_content: new_content

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been updated.", session[:message]

    get "/changes.txt"
    assert_equal 200, last_response.status
    assert_includes last_response.body, new_content
  end

  def test_content_edit_rename
    new_name = 'changes.md'

    post_as_admin '/changes.txt/edit', new_name: new_name

    assert_equal 302, last_response.status
    assert_equal "changes.txt has been renamed to changes.md.", session[:message]

    get last_response["Location"]

    refute_includes last_response.body, "href=\"changes.txt"
    assert_includes last_response.body, "href=\"changes.md"

    get "/changes.md"
    assert_equal 200, last_response.status
    assert_includes last_response.body, "This site is dedicated to history of Ruby language evolution. Basically, it is just the same information that each Ruby versionâ€™s NEWS file contains, just in more readable and informative manner."
  end

  def test_content_edit_rename_invalid
    new_name = 'about.md'
    new_content = 'This is the new content.'
    
    post_as_admin '/changes.txt/edit', new_name: new_name, updated_content: new_content
    
    assert_equal 409, last_response.status
    assert_includes last_response.body, "about.md already exists."
    get 'changes.txt'
    refute_includes last_response.body, new_content
    assert_includes last_response.body, "This site is dedicated to history of Ruby language evolution. Basically, it is just the same information that each Ruby versionâ€™s NEWS file contains, just in more readable and informative manner."

    new_name = 'changes'
    post '/changes.txt/edit', new_name: new_name, update_content: new_content

    assert_equal 415, last_response.status
    assert_includes last_response.body, "The file must be #{supported_types.join(' or ')} file types."
    refute_equal new_content, last_response.body
    get 'changes.txt'
    refute_includes last_response.body, new_content
    assert_includes last_response.body, "This site is dedicated to history of Ruby language evolution. Basically, it is just the same information that each Ruby versionâ€™s NEWS file contains, just in more readable and informative manner."

    new_name = ''
    post '/changes.txt/edit', new_name: new_name, update_content: new_content

    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
    refute_equal new_content, last_response.body
    get 'changes.txt'
    refute_includes last_response.body, new_content
    assert_includes last_response.body, "This site is dedicated to history of Ruby language evolution. Basically, it is just the same information that each Ruby versionâ€™s NEWS file contains, just in more readable and informative manner."
  end

  def test_content_edit_no_change
    post_as_admin '/changes.txt/edit'

    assert_equal 302, last_response.status
    assert_equal "No changes were made to changes.txt.", session[:message]
  end

  def test_content_edit_signed_out
    new_content = "THIS IS A NEW EDIT VIA TESTING - #{Time.now.getutc}"
    post "/changes.txt/edit", updated_content: new_content

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]
  end

  def test_add_new_content_page
    get_as_admin "/new_doc/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Add a new document:"
    assert_includes last_response.body, '<input type="text"'
    assert_includes last_response.body, '<input type="submit"'
  end

  def test_add_new_content_page_signed_out
    get '/new_doc/'

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]
  end

  def test_content_creation
    new_doc = "new.txt"

    post_as_admin '/new_doc/', doc_name: new_doc
    
    assert_equal 302, last_response.status
    assert_equal "#{new_doc} was created.", session[:message]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "href=\"#{new_doc}\""
  end

  def test_content_creation_signed_out
    new_doc = "new.txt"
    post '/new_doc/', doc_name: new_doc

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]
  end

  def test_content_creation_no_name
    post_as_admin '/new_doc/', doc_name: ""

    assert_equal 422, last_response.status
    assert_includes last_response.body, "A name is required."
  end

  def test_content_creation_invalid_type
    post_as_admin '/new_doc/', doc_name: "invalid.invalid"
    
    assert_equal 415, last_response.status
    assert_includes last_response.body, "The file must be #{supported_types.join(' or ')} file types."
  end

  def test_content_creation_no_type
    post_as_admin '/new_doc/', doc_name: 'invalid'
    
    assert_equal 415, last_response.status
    assert_includes last_response.body, "The file must be #{supported_types.join(' or ')} file types."
  end

  def test_content_creation_already_exists
    post_as_admin '/new_doc/', doc_name: 'about.md'
    
    assert_equal 409, last_response.status
    assert_includes last_response.body, "about.md already exists."
  end

  def test_content_deletion
    post_as_admin '/about.md/delete'

    assert_equal 302, last_response.status
    assert_equal 'about.md was deleted.', session[:message]

    get last_response["Location"]
    
    assert_equal 200, last_response.status
    refute_includes last_response.body, '<a href="about.md">'
  end

  def test_content_deletion_signed_out
    post '/about.md/delete'

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]
  end

  def test_content_duplication
    # name should be original document with _copy appended before extension
    # content should be the same as original document
    post_as_admin '/about.md/duplicate'

    assert_equal 302, last_response.status
    assert_equal "about.md was duplicated to about_copy.md.", session[:message]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "href=\"about_copy.md\""
    
    get '/about.md'
    original_content = last_response.body

    get '/about_copy.md'
    assert_equal original_content, last_response.body
  end

  def test_content_duplication_signed_out
    post '/about.md/duplicate'

    assert_equal 302, last_response.status
    assert_equal 'You must be signed in to do that.', session[:message]
  end

  def test_content_duplication_new_name_already_exists
    # _copy should be repeatedly appended before extension until new name is unique
    create_document "about_copy.md", "about_copy"
    create_document "about_copy_copy.md", "about_copy_copy"

    post_as_admin '/about.md/duplicate'

    assert_equal 302, last_response.status
    assert_equal "about.md was duplicated to about_copy_copy_copy.md.", session[:message]

    get last_response["Location"]

    get '/about.md'
    original_content = last_response.body

    get '/about_copy_copy_copy.md'
    assert_equal original_content, last_response.body
  end
end
