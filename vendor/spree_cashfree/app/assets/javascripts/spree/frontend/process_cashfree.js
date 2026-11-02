//= require spree/frontend

var CASHFREE_OPTIONS = '#cashfree-options'
var CASHFREE_BUTTON = '#cashfree-button'

Spree.ready(function ($) {
  let cashfree_btn = $(CASHFREE_BUTTON)
  
  if (cashfree_btn.length > 0) {
    const environment = $(CASHFREE_OPTIONS).data('cf-environment');
    
    // Initialize Cashfree
    const cashfree = Cashfree({
      mode: environment === 'production' ? 'production' : 'sandbox'
    });

    const checkoutOptions = {
      paymentSessionId: $(CASHFREE_OPTIONS).data('cf-payment-session-id'),
      returnUrl: $(CASHFREE_OPTIONS).data('cf-return-url'),
      customerDetails: {
        customerId: $(CASHFREE_OPTIONS).data('cf-customer-id'),
        customerName: $(CASHFREE_OPTIONS).data('cf-customer-name'),
        customerEmail: $(CASHFREE_OPTIONS).data('cf-customer-email'),
        customerPhone: $(CASHFREE_OPTIONS).data('cf-customer-phone')
      },
      paymentMethods: {},
      theme: {
        color: $(CASHFREE_OPTIONS).data('cf-theme-color')
      }
    };

    $(CASHFREE_BUTTON).on("click", function(e) {
      e.preventDefault();
      cashfree.checkout(checkoutOptions);
    });
  }
});