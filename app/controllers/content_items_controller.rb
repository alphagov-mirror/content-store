require 'govuk/client/url_arbiter'

class ContentItemsController < ApplicationController
  before_filter :parse_json_request, :only => [:update]
  before_filter :register_with_url_arbiter, :only => [:update]

  def show
    item = Rails.application.statsd.time('show.find_by') do
      ContentItem.find_by(:base_path => encoded_base_path)
    end

    expires_at config.default_ttl.from_now

    # The presenter needs context about routes and host names from controller
    # to know how to generate API URLs, so we can take the Rails helper and
    # pass that in as a callable
    api_url_method = method(:content_item_url)
    presenter = PublicContentItemPresenter.new(item, api_url_method)

    render :json => presenter
  end

  def update
    result, item = Rails.application.statsd.time('update.create_or_replace') do
      ContentItem.create_or_replace(encoded_base_path, @request_data)
    end

    if result
      status = (result == :created ? :created : :ok)
    else
      status = :unprocessable_entity
    end
    render :json => PrivateContentItemPresenter.new(item), :status => status
  end

  private

  def parse_json_request
    @request_data = JSON.parse(request.body.read).except('base_path')
  rescue JSON::ParserError
    head :bad_request
  end

  def register_with_url_arbiter
    Rails.application.url_arbiter_api.reserve_path(encoded_base_path, "publishing_app" => @request_data["publishing_app"])
  rescue GOVUK::Client::Errors::Conflict => e
    return_arbiter_error(:conflict, e)
  rescue GOVUK::Client::Errors::UnprocessableEntity => e
    return_arbiter_error(:unprocessable_entity, e)
  end

  def return_arbiter_error(status, exception)
    item = ContentItem.new(@request_data.merge("base_path" => encoded_base_path))
    if exception.response["errors"]
      exception.response["errors"].each do |field, errors|
        errors.each do |error|
          item.errors.add("url_arbiter_registration", "#{field} #{error}")
        end
      end
    else
      item.errors.add("url_arbiter_registration", "#{exception.response.code}: #{exception.response.raw_body}")
    end
    render :json => PrivateContentItemPresenter.new(item), :status => status
  end

  def base_path
    params["base_path"]
  end

  def encoded_base_path
    URI.escape(base_path)
  end
end
