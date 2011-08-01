class ExternalGateway < PaymentMethod

  require 'digest/sha1'
  require 'date'
    
  #We need access to routes to correctly assemble a return url
 include ActionController::UrlWriter

  #This is normally set in the Admin UI - the server in this case is where to redirect to.
  preference :server, :string

  #This holds JSON data - I've kind of had to make an assumption here that the gateway you use will pass this parameter through.
  #The particular gateway I am using does not accept URL parameters, it seems.
  preference :custom_data, :string
  #When the gateway redirects back to the return URL, it will usually include some parameters of its own
  #indicating the status of the transaction. The following two preferences indicate which parameter keys this
  #class should look for to detect whether the payment went through successfully.
  # {status_param_key} is the params key that holds the transaction status.
  # {successful_transaction_value} is the value that indicates success - this is usually a number.

  preference :status_param_key, :string, :default => 'status'
  preference :successful_transaction_value, :string, :default => 'success'
  
    # Rabobank iDEAL Lite - specific methods added by: Arjan Landman
  
  #hardcoded
  preference :language, :string, :default => "nl"
  preference :subID, :string, :default => "0"
  preference :currency, :string, :default => "EUR"
  preference :paymentType, :string, :default => "ideal"
  preference :hash, :string, :default => "SHA-1"
  
  # from admin => DB
  preference :merchantID, :string, :default => "002031546"
  preference :description, :string, :default => "Evans & Watson"
 # preference :urlSuccess, :string, :default => "http://127.0.0.1/checkout/confirm/"
 # preference :urlCancel, :string, :default => "http://127.0.0.1/checkout/payment/"
 # preference :urlError, :string, :default => "http://127.0.0.1/checkout/payment/error"
  preference :secret, :string, :default => "eju2c5CoRHZlHoTc"

  #An array of preferences that should not be automatically inserted into the form
  INTERNAL_PREFERENCES = [:server, :status_param_key, :successful_transaction_value, :custom_data]

  #Arbitrarily, this class is called ExternalGateway, but the extension is a whole is named 'HostedGateway', so
  #this is what we want our checkout/admin view partials to be named.
  def method_type
    "hosted_gateway"
  end

  #Process response detects the status of a payment made through an external gateway by looking
  #for a success value (as configured in the successful_transaction_value preference), in a particular
  #parameter (as configured in the status_param_key preference).
  #For convenience, and to validate the incoming response from the gateway somewhat, it also attempts
  #to find the order from the parameters we sent the gateway as part of the return URL and returns it
  #along with the transaction status.
  def process_response(params)
    begin
      #Find order
      order = Order.find_by_number(ExternalGateway.parse_custom_data(params)["order_number"])
      raise ActiveRecord::RecordNotFound if order.token != ExternalGateway.parse_custom_data(params)["order_token"]

      #Check for successful response
      transaction_succeeded = params[self.preferred_status_param_key.to_sym] == self.preferred_successful_transaction_value.to_s
      return [order, transaction_succeeded]
    rescue ActiveRecord::RecordNotFound
      #Return nil and false if we couldn't find the order - this is probably bad.
      return [nil, false]
    end
  end

  #This is basically a attr_reader for server, but makes sure that it has been set.
  def get_server
    if self.preferred_server
      return self.preferred_server
    else
      raise "You need to configure a server to use an external gateway as a payment type!"
    end
  end

  #At a minimum, you should use this field to POST the order number and payment method id - but you can
  #always override it to do something else.
  def get_custom_data_for(order)
    return {"order_number" => order.number, "payment_method_id" => self.id, "order_token" => order.token}.to_json
  end

  #This is another case of stupid payment gateways, but does allow you to
  #store your custom data in whatever format you want, and then parse it
  #the same way. The only caveat is to make sure it returns a hash so
  #that the controller can find what it needs to.
  #By default, we try and parse JSON out of the param.
  def self.parse_custom_data(params)
    return ActiveSupport::JSON.decode(params[:custom_data])
  end


  #The payment gateway I'm using only accepts rounded-dollar amounts. Stupid.
  #I've added this method nonetheless, so that I can easily override it to round the amount
  def get_total_for(order)
    return order.total
  end

  #This is another attr_reader, but does a couple of necessary things to make sure we can keep track
  #of the transaction, even with multiple orders going on at different times.
  #By passing in a boolean to determine if the user is on an
  #admin checkout page (in which case we need to redirect to a different path), a full return url can be
  #assembled that will redirect back to the correct page
  #to complete the order.
  def get_return_url_for(order, on_admin_page = false)
    if on_admin_page
      return admin_gateway_landing_url(:host => Spree::Config[:site_url])
    else
      return gateway_landing_url(:host => Spree::Config[:site_url])
    end
  end

  #This method basically takes the preferences of the class, removing items that should not be POST'd to
  #the payment gateway, such as server, and the parameter name of the transaction success/failure field.
  #This method allows users to add preferences using class_eval, which should automatically be picked up
  #by this method and inserted into relevant forms as hidden fields.
  def additional_attributes
    self.preferences.select { |key| !INTERNAL_PREFERENCES.include?(key[0].to_sym) }
  end
  
  
  #added generating method
  def get_ideal(order)
  	get_hash(order)
  end
  
  def get_merchantID
  	return self.preferences["merchantID"]
  end
  
  def get_subID
  	return self.preferences["subID"]
  end
  
  def get_purchaseID(order)
  	return order.number.to_s() + "\n"
  end
  
  def get_amount(order)
    order_item_total = order.item_total.to_f * 100
    order_adjustment_total = order.adjustment_total.to_f * 100
    order_total = order_item_total + order_adjustment_total
    return order_total.round
  end
  
  def get_currency
  	return self.preferences["currency"]
  end
  
  def get_language
  	return self.preferences["language"]
  end
  
  def get_validUntil(order)
  	t = Time.now + 2.hours
  	validuntil = t.strftime("%Y-%m-%d %H:%M:%S.%Z") 
  	return validuntil
  end 
  
  def add_btw(order)
  	order_btw = order.tax_total.to_f * 100
  	product = {
      :id => "9998",
      :desc => "BTW",
      :quantity => "1",
      :price => order_btw.round.to_s() + "\n"
    }
    return product
  end
  
  def add_shipping(order)
	ship_cost = order.ship_total.to_f * 100
    product = {
      :id => "9999",
      :desc => "Verzendkosten",
      :quantity => "1",
      :price => ship_cost.round.to_s() + "\n"
    }
    return product
  end   	  

  # get products in array
    def get_products(order)
	products = Array.new();
	
		order.products.each_with_index do |product, i|
			product_price = product.price.to_f * 100			
			products[i] = {
				:id => product.id,
				:desc => product.name, 
				:quantity => order.line_items[0].quantity,
				:price => product_price.round.to_s() + "\n"
			}
		end
	products[products.length] = add_btw(order) + add_shipping(order)
		return products	
  end   
  
  def get_paymentType
 	return self.preferences["paymentType"]
  end
  
  
  

end

