module HostedGateway
  module CheckoutControllerExt
    def self.included(base)
      base.class_eval do
		
        skip_before_filter :load_order, :only => [:process_gateway_return]
        #We need to skip this security check Rails does in order to let the payment gateway do a postback.
        skip_before_filter :verify_authenticity_token, :only => [:process_gateway_return]

        #TODO? This method is more or less copied from the normal controller - so this sort
        #of this is prone to messing up updates - maybe we could use alias_method_chain or something?
       
        def process_gateway_return
              
          gateway = PaymentMethod.find_by_type_and_name("ExternalGateway", "iDEAL")
          @order = Order.find_by_id(params[:id])
          order = params[:id]
          idealstatus = params[:status] #== "success"
	

          if @order && idealstatus == "success"
            #Payment successfully processed
            @order.payments.clear
            payment = @order.payments.create
            payment.started_processing
            payment.amount = params[:amount] || @order.total
            payment.payment_method = gateway
            payment.complete
            @order.save

            if @order.next
              state_callback(:after)
            end

            if @order.state == "complete" or @order.completed?
              flash[:notice] = "Uw betaling met iDEAL is geslaagd."
              #flash[:commerce_tracking] = "nothing special"
              redirect_to completion_route
            else
              redirect_to checkout_state_path(@order.state)
            end
          elsif @order && idealstatus == "cancel"
            # Payment canceld by
            flash[:error] = "U heeft de betaling met iDEAL afgebroken."
            redirect_to checkout_state_path(@order.state)
          else
            #Error processing payment
             flash[:error] = "De order kan niet gevonden worden of we hebben van uw bank nog geen bevestiging ontvangen. Als u in uw Internetbankieren ziet dat uw betaling heeft plaatsgevonden, zullen wij na ontvangst van de betaling tot levering overgaan."
            redirect_to checkout_state_path(@order.state) and return
          end
        end
      end
    end
  end
end
