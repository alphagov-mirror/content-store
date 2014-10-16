class QueuePublisher
  def initialize(options = {})
    @noop = options[:noop]
    return if @noop

    @exchange_name = options.fetch(:exchange)
    @options = options.except(:exchange)

    @connection = Bunny.new(@options)
    @connection.start
  end

  def exchange
    @exchange ||= connect_to_exchange
  end

  class PublishFailedError < StandardError
  end

  def send_message(item)
    return if @noop
    routing_key = "#{item.format}.#{item.update_type}"
    exchange.publish(
      item_json(item),
      routing_key: routing_key,
      content_type: 'application/json',
      persistent: true
    )
    success = exchange.wait_for_confirms
    if !success
      Airbrake.notify_or_ignore(
        PublishFailedError.new("Publishing message failed"),
        parameters: {
          routing_key: routing_key,
          message_body: hash,
        },
      )
    end
  end

  private

  def connect_to_exchange
    @channel = @connection.create_channel

    # Enable publisher confirms, so we get acks back after publishes.
    @channel.confirm_select

    # passive parameter ensures we don't create the exchange.
    @channel.topic(@exchange_name, passive: true)
  end

  def item_json(item)
    PrivateContentItemPresenter.new(item).to_json
  end
end

