Feature: signup
  As a new user
  I want to sign up to the site
  So I can have fun using its features

  @selenium
  Scenario: successfull registration
    Given I am on the homepage
    When I follow "Login"
    And I follow "New user"
    And I fill in the following within ".no-boxes":
      | E-mail                | josesilva@example.com |
      | Username              | josesilva             |
      | Password              | secret                |
      | Password confirmation | secret                |
      | Full name             | José da Silva         |
    And wait for the captcha signup time
    And I follow "Create my account"
    And there are no pending jobs
    Then I should receive an e-mail on josesilva@example.com
    When I go to login page
    And I fill in "Username" with "josesilva"
    And I fill in "Password" with "secret"
    And I follow "Log in"
    Then I should not be logged in as "josesilva"
    When José da Silva's account is activated
    And I go to login page
    And I fill in "Username" with "josesilva"
    And I fill in "Password" with "secret"
    And I follow "Log in"
    Then I should be logged in as "josesilva"

  @selenium
  Scenario: show error message if username is already used
    Given the following users
      | login     |
      | josesilva |
    When I go to signup page
    And I fill in "Username" with "josesilva"
    And I fill in "E-mail" with "josesilva1"
    Then I should see "This login name is unavailable"

  Scenario: be redirected if user goes to signup page and is logged
    Given the following users
      | login | name |
      | joaosilva | joao silva |
    Given I am logged in as "joaosilva"
    And I go to signup page
    Then I should be on joaosilva's control panel

  @selenium
  Scenario: user cannot register without a name
    Given I am on the homepage
    And I follow "Login"
    And I follow "New user"
    And I fill in "E-mail" with "josesilva@example.com"
    And I fill in "Username" with "josesilva"
    And I fill in "Password" with "secret"
    And I fill in "Password confirmation" with "secret"
    And wait for the captcha signup time
    And I follow "Create my account"
    Then I should see "Name can't be blank"

  Scenario: user cannot change his name to empty string
    Given the following users
      | login | name |
      | joaosilva | Joao Silva |
    Given I am logged in as "joaosilva"
    And I am on joaosilva's control panel
    And I follow "Edit Profile"
    And I fill in "Name" with ""
    When I press "Save"
    Then I should see "Name can't be blank"
