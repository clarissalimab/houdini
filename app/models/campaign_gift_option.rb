# frozen_string_literal: true

# License: AGPL-3.0-or-later WITH WTO-AP-3.0-or-later
# Full license explanation at https://github.com/houdiniproject/houdini/blob/master/LICENSE
class CampaignGiftOption < ApplicationRecord
  include Model::Eventable
  include Model::Jbuilder

  # :amount_one_time, #int (cents)
  # :amount_recurring, #int (cents)
  # :amount_dollars, #str, gets converted to amount
  # :description, # text
  # :name, # str
  # :campaign, #assocation
  # :quantity, #int (optional)
  # :to_ship, #boolean
  # :order, #int (optional)
  # :hide_contributions #boolean (optional)

  belongs_to :campaign
  has_many :campaign_gifts
  has_many :donations, through: :campaign_gifts

  validates :name, presence: true
  validates :campaign, presence: true
  validates :amount_one_time,  presence: true, numericality: { only_integer: true }, unless: :amount_recurring
  validates :amount_recurring, presence: true, numericality: { only_integer: true }, unless: :amount_one_time

  after_create_commit :publish_created
  after_update_commit :publish_updated
  after_destroy_commit :publish_deleted

  has_one :nonprofit, through: :campaign


  def total_gifts
    campaign_gifts.count
  end

  def as_json(options = {})
    h = super(options)
    h[:total_gifts] = total_gifts
    h
  end

  def to_builder(*expand)

    gift_option_amount = []
    if amount_one_time
      gift_option_amount.push({
        amount:{
          cents: amount_one_time, 
          currency: campaign.nonprofit.currency
        }
      })
    end

    if amount_recurring
      gift_option_amount.push({
        amount:{
          cents: amount_recurring, 
          currency: campaign.nonprofit.currency
        },
        recurrence: {
          type: 'monthly',
          interval: 1
        }
      })
    end

    init_builder(*expand) do |json|
      json.(self, :name, :description, 
          :hide_contributions, :order, :to_ship)

      if quantity
        json.quantity quantity
      end

      json.deleted !persisted?

      json.gift_option_amount gift_option_amount do |desc|
        json.amount do 
          json.currency desc[:amount][:currency]
          json.cents desc[:amount][:cents]
        end
        json.recurrence do 
          json.interval desc[:recurrence][:interval]
          json.type desc[:recurrence][:type]
        end if desc[:recurrence]
      end

      json.add_builder_expansion :campaign, :nonprofit
    end
  end

  private
  def publish_created
    Houdini.event_publisher.announce(:campaign_gift_option_created, to_event('campaign_gift_option.created', :nonprofit, :campaign).attributes!)
  end

  def publish_updated
    Houdini.event_publisher.announce(:campaign_gift_option_updated, to_event('campaign_gift_option.updated', :nonprofit, :campaign).attributes!)
  end

  def publish_deleted
    Houdini.event_publisher.announce(:campaign_gift_option_deleted, to_event('campaign_gift_option.deleted', :nonprofit, :campaign).attributes!)
  end
end
