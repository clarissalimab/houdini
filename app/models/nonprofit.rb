# frozen_string_literal: true

# License: AGPL-3.0-or-later WITH Web-Template-Output-Additional-Permission-3.0-or-later
class Nonprofit < ApplicationRecord
  attr_accessor :register_np_only, :user
  Categories = ['Public Benefit', 'Human Services', 'Education', 'Civic Duty', 'Human Rights', 'Animals', 'Environment', 'Health', 'Arts, Culture, Humanities', 'International', 'Children', 'Religion', 'LGBTQ', "Women's Rights", 'Disaster Relief', 'Veterans'].freeze

  # :name, # str
  # :stripe_account_id, # str
  # :summary, # text: paragraph-sized organization summary
  # :tagline, # str
  # :email, # str: public organization contact email
  # :phone, # str: public org contact phone
  # :main_image, # str: url of featured image - first image in profile carousel
  # :second_image, # str: url of 2nd image in carousel
  # :third_image, # str: url of 3rd image in carousel
  # :background_image,  # str: url of large profile background
  # :remove_background_image, #bool carrierwave
  # :logo, # str: small logo image url for searching
  # :zip_code, # int
  # :website, # str: their own website url
  # :categories, # text [str]: see the constant Categories
  # :achievements, # text [str]: highlights about this org
  # :full_description, # text
  # :state_code, # str: two-letter state code (eg. CA)
  # :statement, # str: bank statement for donations towards the nonprofit
  # :city, # str
  # :slug, # str
  # :city_slug, #str
  # :state_code_slug, #str
  # :ein, # str: employee identification number
  # :published, # boolean; whether to display this profile
  # :vetted, # bool: Whether a super admin (one of CommitChange's employees) have approved this org
  # :verification_status, # str (either 'pending', 'unverified', 'escalated', 'verified' -- whether the org has submitted the identity verification form and it has been approved)
  # :latitude, # float: geocoder gem
  # :longitude, # float: geocoder gem
  # :timezone, # str
  # :address, # text
  # :thank_you_note, # text
  # :referrer, # str
  # :no_anon, # bool: whether to allow anonymous donations
  # :roles_attributes,
  # :brand_font, #string (lowercase key eg. 'helvetica')
  # :brand_color, #string (hex color value)
  # :hide_activity_feed, # bool
  # :tracking_script,
  # :facebook, #string (url)
  # :twitter, #string (url)
  # :youtube, #string (url)
  # :instagram, #string (url)
  # :blog, #string (url)
  # :card_failure_message_top, # text
  # :card_failure_message_bottom, # text
  # :autocomplete_supporter_address # boolean

  has_many :payouts
  has_many :charges
  has_many :refunds, through: :charges
  has_many :donations
  has_many :recurring_donations
  has_many :payments
  has_many :supporters, dependent: :destroy
  has_many :supporter_notes, through: :supporters
  has_many :profiles, through: :donations
  has_many :campaigns, dependent: :destroy
  has_many :events, dependent: :destroy
  has_many :tickets, through: :events
  has_many :users, through: :roles
  has_many :tag_masters, dependent: :destroy
  has_many :custom_field_masters, dependent: :destroy
  has_many :roles,        as: :host, dependent: :destroy
  has_many :activities,   as: :host, dependent: :destroy
  has_many :imports
  has_many :email_settings
  has_many :cards, as: :holder

  has_one :bank_account, -> { where('COALESCE(deleted, false) = false') },
          dependent: :destroy
  has_one :billing_subscription, dependent: :destroy
  has_one :billing_plan, through: :billing_subscription
  has_one :miscellaneous_np_info

  ##only meaningful on registration
  has_one :user

  validates :name, presence: true
  validates :city, presence: true
  validates :state_code, presence: true
  validates :email, format: { with: Email::Regex }, allow_blank: true
  validates_uniqueness_of :slug, scope: %i[city_slug state_code_slug]
  validates_presence_of :slug
  
  validates_presence_of :user, on: :create, unless: -> {register_np_only}
  validate :user_registerable_as_admin, on: :create, unless: -> {register_np_only}

  scope :vetted, -> { where(vetted: true) }
  scope :identity_verified, -> { where(verification_status: 'verified') }
  scope :published, -> { where(published: true) }

  mount_uploader :main_image, NonprofitUploader
  mount_uploader :second_image, NonprofitUploader
  mount_uploader :third_image, NonprofitUploader
  mount_uploader :background_image, NonprofitBackgroundUploader
  mount_uploader :logo, NonprofitLogoUploader

  serialize :achievements, Array
  serialize :categories, Array

  geocoded_by :full_address

  before_validation(on: :create) do
    set_slugs
    self
  end

  after_validation(on: :create) do
    correct_nonunique_slug
  end

  after_create :build_admin_role, unless: -> {register_np_only}

  # Register (create) a nonprofit with an initial admin
  def self.register(user, params)
    np = create ConstructNonprofit.construct(user, params)
    role = Role.create(user: user, name: 'nonprofit_admin', host: np) if np.valid?
    np
  end

  def nonprofit_personnel_emails
    roles.nonprofit_personnel.joins(:user).pluck('users.email')
  end

  def total_recurring
    recurring_donations.active.sum(:amount)
  end

  def donation_history_monthly
    donation_history_monthly = []
    donations.order('created_at')
             .group_by { |d| d.created_at.beginning_of_month }
             .each { |_, ds| donation_history_monthly.push(ds.map(&:amount).sum) }
    donation_history_monthly
  end

  def as_json(options = {})
    h = super(options)
    h[:url] = url
    h
  end

  def url
    "/#{state_code_slug}/#{city_slug}/#{slug}"
  end

  def set_slugs
    self.slug = Format::Url.convert_to_slug name unless slug
    self.city_slug = Format::Url.convert_to_slug city unless city_slug

    unless state_code_slug
      self.state_code_slug = Format::Url.convert_to_slug state_code
    end
    self
  end
  
  def correct_nonunique_slug
    if errors[:slug]
      begin
          slug = SlugNonprofitNamingAlgorithm.new(self.state_code_slug, self.city_slug).create_copy_name(self.slug)
          self.slug = slug
      rescue UnableToCreateNameCopyError
      end
    end
  end

  def full_address
    Format::Address.full_address(address, city, state_code)
  end

  def total_raised
    QueryPayments.get_payout_totals(QueryPayments.ids_for_payout(id))['net_amount']
  end

  def can_make_payouts
    vetted &&
      verification_status == 'verified' &&
      bank_account &&
      !bank_account.pending_verification
  end

  def active_cards
    cards.where('COALESCE(cards.inactive, FALSE) = FALSE')
  end

  # @param [Card] card the new active_card
  def active_card=(card)
    unless card.class == Card
      raise ArgumentError, 'Pass a card to active_card or else'
    end

    Card.transaction do
      active_cards.update_all inactive: true
      return cards << card
    end
  end

  def active_card
    active_cards.first
  end

  def create_active_card(card_data)
    if card_data[:inactive]
      raise ArgumentError, 'This method is for creating active cards only'
    end

    active_cards.update_all inactive: true
    cards.create(card_data)
  end

  def currency_symbol
    Settings.intntl.all_currencies.find { |i| i.abbv.casecmp(currency).zero? }&.symbol
  end

  def user_registerable_as_admin
    if user && user.roles.nonprofit_admins.any?
      errors.add(:user, "cannot already be an admin for a nonprofit.")
    end
  end
private 
  def build_admin_role 
    role = user.roles.build(host: self, name: 'nonprofit_admin')
    role.save!
  end

  def add_billing_subscription
    billing_plan = BillingPlan.find(Settings.default_bp.id)
    b_sub = build_billing_subscription(billing_plan: billing_plan, status: 'active')
    b_sub.save!
  end
end
