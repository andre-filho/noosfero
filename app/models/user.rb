require 'digest/sha1'

# User models the system users, and is generated by the acts_as_authenticated
# Rails generator.
class User < ActiveRecord::Base

  N_('Password')
  N_('Password confirmation')
  N_('Terms accepted')

  def self.[](login)
    self.find_by_login(login)
  end

  # FIXME ugly workaround
  def self.human_attribute_name(attrib)
    case attrib.to_sym
      when :login:  return _('Username')
      when :email:  return _('e-Mail')
      else _(self.superclass.human_attribute_name(attrib))
    end
  end

  before_create do |user|
    if user.environment.nil?
      user.environment = Environment.default
    end
    user.send(:make_activation_code) unless user.environment.enabled?('skip_new_user_email_confirmation')
  end

  after_create do |user|
    user.person ||= Person.new
    user.person.attributes = user.person_data.merge(:identifier => user.login, :user_id => user.id, :environment_id => user.environment_id)
    user.person.name ||= user.login
    user.person.visible = false unless user.activated?
    user.person.save!
    if user.environment.enabled?('skip_new_user_email_confirmation')
      user.activate
    end
  end
  after_create :deliver_activation_code
  after_create :delay_activation_check

  attr_writer :person_data
  def person_data
    @person_data || {}
  end

  def email_domain
    self.person.preferred_domain && self.person.preferred_domain.name || self.environment.default_hostname(true)
  end

  class Mailer < ActionMailer::Base
    def activation_email_notify(user)
      user_email = "#{user.login}@#{user.email_domain}"
      recipients user_email
      from "#{user.environment.name} <#{user.environment.contact_email}>"
      subject _("[%{environment}] Welcome to %{environment} mail!") % { :environment => user.environment.name }
      body :name => user.name,
        :email => user_email,
        :webmail => MailConf.webmail_url(user.login, user.email_domain),
        :environment => user.environment.name,
        :url => url_for(:host => user.environment.default_hostname, :controller => 'home')
    end

    def activation_code(user)
      recipients user.email

      from "#{user.environment.name} <#{user.environment.contact_email}>"
      subject _("[%s] Activate your account") % [user.environment.name]
      body :recipient => user.name,
        :activation_code => user.activation_code,
        :environment => user.environment.name,
        :url => user.environment.top_url
    end
  end

  def signup!
    User.transaction do
      self.save!
      self.person.save!
    end
  end
  
  has_one :person, :dependent => :destroy
  belongs_to :environment

  attr_protected :activated_at

  # Virtual attribute for the unencrypted password
  attr_accessor :password

  validates_presence_of     :login, :email
  validates_format_of       :login, :with => Profile::IDENTIFIER_FORMAT, :if => (lambda {|user| !user.login.blank?})
  validates_presence_of     :password,                   :if => :password_required?
  validates_presence_of     :password_confirmation,      :if => :password_required?, :if => (lambda {|user| !user.password.blank?})
  validates_length_of       :password, :within => 4..40, :if => :password_required?, :if => (lambda {|user| !user.password.blank?})
  validates_confirmation_of :password,                   :if => :password_required?
  validates_length_of       :login,    :within => 2..40, :if => (lambda {|user| !user.login.blank?})
  validates_length_of       :email,    :within => 3..100, :if => (lambda {|user| !user.email.blank?})
  validates_uniqueness_of   :login, :email, :case_sensitive => false, :scope => :environment_id
  before_save :encrypt_password
  validates_format_of :email, :with => Noosfero::Constants::EMAIL_FORMAT, :if => (lambda {|user| !user.email.blank?})

  validates_inclusion_of :terms_accepted, :in => [ '1' ], :if => lambda { |u| ! u.terms_of_use.blank? }, :message => N_('%{fn} must be checked in order to signup.').fix_i18n

  # Authenticates a user by their login name and unencrypted password.  Returns the user or nil.
  def self.authenticate(login, password, environment = nil)
    environment ||= Environment.default
    u = first :conditions => ['login = ? AND environment_id = ? AND activated_at IS NOT NULL', login, environment.id] # need to get the salt
    u && u.authenticated?(password) ? u : nil
  end

  # Activates the user in the database.
  def activate
    return false unless self.person
    self.activated_at = Time.now.utc
    self.activation_code = nil
    self.person.visible = true
    self.person.save! && self.save!
  end

  def activated?
    self.activation_code.nil? && !self.activated_at.nil?
  end

  class UnsupportedEncryptionType < Exception; end

  def self.system_encryption_method
    @system_encryption_method || :salted_sha1
  end

  def self.system_encryption_method=(method)
    @system_encryption_method = method
  end

  # a Hash containing the available encryption methods. Keys are symbols,
  # values are Proc objects that contain the actual encryption code.
  def self.encryption_methods
    @encryption_methods ||= {}
  end

  # adds a new encryption method.
  def self.add_encryption_method(sym, &block)
    encryption_methods[sym] = block
  end

  # the encryption method used for this instance 
  def encryption_method
    (password_type || User.system_encryption_method).to_sym
  end

  # Encrypts the password using the chosen method
  def encrypt(password)
    method = self.class.encryption_methods[encryption_method]
    if method
      method.call(password, salt)
    else
      raise UnsupportedEncryptionType, "Unsupported encryption type: #{encryption_method}"
    end
  end

  add_encryption_method :salted_sha1 do |password, salt|
    Digest::SHA1.hexdigest("--#{salt}--#{password}--")
  end

  add_encryption_method :md5 do |password, salt|
    Digest::MD5.hexdigest(password)
  end

  add_encryption_method :clear do |password, salt|
    password
  end

  add_encryption_method :crypt do |password, salt|
    password.crypt(salt)
  end

  def authenticated?(password)
    result = (crypted_password == encrypt(password))
    if (encryption_method != User.system_encryption_method) && result
      self.password_type = User.system_encryption_method.to_s
      self.password = password
      self.password_confirmation = password
      self.save!
    end
    result
  end

  def remember_token?
    remember_token_expires_at && Time.now.utc < remember_token_expires_at 
  end

  # These create and unset the fields required for remembering users between browser closes
  def remember_me
    self.remember_token_expires_at = 2.weeks.from_now.utc
    self.remember_token            = encrypt("#{email}--#{remember_token_expires_at}")
    save(false)
  end

  def forget_me
    self.remember_token_expires_at = nil
    self.remember_token            = nil
    save(false)
  end

  # Exception thrown when #change_password! is called with a wrong current
  # password
  class IncorrectPassword < Exception; end

  # Changes the password of a user.
  #
  # * Raises IncorrectPassword if <tt>current</tt> is different from the user's
  #   current password.
  # * Saves the record unless it is a new one.
  def change_password!(current, new, confirmation)
    raise IncorrectPassword unless self.authenticated?(current)
    self.force_change_password!(new, confirmation)
  end
  
  # Changes the password of a user without asking for the old password. This
  # method is intended to be used by the "I forgot my password", and must be
  # used with care.
  def force_change_password!(new, confirmation)
    self.password = new
    self.password_confirmation = confirmation
    save! unless new_record?
  end

  def name
    person ? person.name : login
  end

  def enable_email!
    self.update_attribute(:enable_email, true)
  end

  def disable_email!
    self.update_attribute(:enable_email, false)
  end

  def email_activation_pending?
    if self.environment.nil?
      return false
    else
      return EmailActivation.exists?(:requestor_id => self.person.id, :target_id => self.environment.id, :status => Task::Status::ACTIVE)
    end
  end

  def data_hash
    friends_list = {}
    enterprises = person.enterprises.map { |e| { 'name' => e.short_name, 'identifier' => e.identifier } }
    self.person.friends.online.map do |person|
      friends_list[person.identifier] = {
        'avatar' => person.profile_custom_icon,
        'name' => person.short_name,
        'jid' => person.full_jid,
        'status' => person.user.chat_status,
      }
    end
    {
      'login' => self.login,
      'is_admin' => self.person.is_admin?,
      'since_month' => self.person.created_at.month,
      'since_year' => self.person.created_at.year,
      'email_domain' => self.enable_email ? self.email_domain : nil,
      'friends_list' => friends_list,
      'enterprises' => enterprises,
      'amount_of_friends' => friends_list.count
    }
  end

  def self.expires_chat_status_every
    15 # in minutes
  end

  protected
    # before filter 
    def encrypt_password
      return if password.blank?
      self.salt ||= Digest::SHA1.hexdigest("--#{Time.now.to_s}--#{login}--") if new_record?
      self.password_type ||= User.system_encryption_method.to_s
      self.crypted_password = encrypt(password)
    end
    
    def password_required?
      crypted_password.blank? || !password.blank?
    end

    def make_activation_code
      self.activation_code = Digest::SHA1.hexdigest(Time.now.to_s.split(//).sort_by{rand}.join)
    end

    def deliver_activation_code
      return if person.is_template?
      User::Mailer.deliver_activation_code(self) unless self.activation_code.blank?
    end

    def delay_activation_check
      Delayed::Job.enqueue(UserActivationJob.new(self.id), 0, 72.hours.from_now)
    end
end
