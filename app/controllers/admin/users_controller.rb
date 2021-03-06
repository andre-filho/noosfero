
class UsersController < AdminController

  protect 'manage_environment_users', :environment

  before_filter :set_person, except: [:index, :download, :send_mail]

  include UsersHelper

  def index
    @collection = filter_users(per_page: per_page, page: params[:npage])
  end

  def set_admin_role
    environment.add_admin(@person)
    redirect_to :action => :index, :q => params[:q], :filter => params[:filter]
  end

  def reset_admin_role
    environment.remove_admin(@person)
    redirect_to :action => :index, :q => params[:q], :filter => params[:filter]
  end

  def activate
    @person.user.activate!
    redirect_to :action => :index, :q => params[:q], :filter => params[:filter]
  end

  def deactivate
    @person.user.deactivate
    redirect_to :action => :index, :q => params[:q], :filter => params[:filter]
  end

  def destroy_user
    if request.post?
      person = environment.people.find_by id: params[:id]
      if person && person.destroy
        session[:notice] = _('The profile was deleted.')
      else
        session[:notice] = _('Could not remove profile')
      end
    end
    redirect_to :action => :index, :q => params[:q], :filter => params[:filter]
  end

  def download
    users = filter_users(per_page: environment.users.count, page: nil)
    exporter = Exporter.new(users, Person.exportable_fields(environment))
    date = Time.current.strftime('%Y-%m-%d %Hh%Mm')
    filename = _('%s people list - %s') % [environment.name, date]

    respond_to do |format|
      format.xml do
        send_data exporter.to_xml, type: 'text/xml', filename: "#{filename}.xml"
      end
      format.csv do
        send_data exporter.to_csv, type: 'text/csv', filename: "#{filename}.csv"
      end
    end
  end

  def send_mail
    if request.post?
      @mailing = environment.mailings.build(params[:mailing])
      @mailing.recipients_roles = []
      @mailing.recipients_roles << "profile_admin" if params[:recipients][:profile_admins].include?("true")
      @mailing.recipients_roles << "environment_administrator" if params[:recipients][:env_admins].include?("true")
      @mailing.locale = locale
      @mailing.person = user
      if @mailing.save
        session[:notice] = _('The e-mails are being sent')
        redirect_to :action => 'index'
      else
        session[:notice] = _('Could not create the e-mail')
      end
    end
  end

  private

  def per_page
    10
  end

  def filter_users(pagination_opts)
    @filter = params[:filter] || 'all_users'
    @q = params[:q]

    scope = environment.people.no_templates
    if @filter == 'admin_users'
      scope = scope.admins
    elsif @filter == 'activated_users'
      scope = scope.activated
    elsif @filter == 'deactivated_users'
      scope = scope.deactivated
    elsif @filter == 'recently_logged_users'
      days = 90
      scope = scope.recent

      if params[:filter_number_of_days] == nil
        scope = scope.where('last_login_at > ?', (Date.today - 0))
      else
        days = 100000
        hash = params[:filter_number_of_days]
        days = hash[:"{:controller=>\"user\", :action=>\"index\"}"]
        scope = scope.where('last_login_at > ?', (Date.today - days.to_i))
      end
    end

    scope = scope.order('name ASC')
    find_by_contents(:people, environment, scope, params[:q],
                     pagination_opts)[:results]
  end

  def set_person
    @person = environment.people.find_by(id: params[:id])
  end
end
