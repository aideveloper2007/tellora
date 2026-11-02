require 'spec_helper'

describe Spree::CcavenueController do
  include RSpec::Rails::ControllerExampleGroup
  include Devise::TestHelpers

  before(:all) do
    @payment_method = FactoryGirl.create(:ccavenue_payment_gateway)
  end

  after(:all) do
    Spree::Gateway::Ccavenue.destroy_all
  end

  it 'should have Spree::Gateway::Ccavenue as an available payment method' do
    Spree::PaymentMethod.available.select{|pm| pm.class == Spree::Gateway::Ccavenue}.count.should == 1
  end

  #context "show" do
  #  before do
  #    @order = Factory(:order)
  #  end
  #
  #  it "raise error when order is not found" do
  #    get :show, { :order_id => "R98762311", :payment_method_id => @payment_method.id, :use_route => :spree }
  #    flash[:error].should_not be_nil
  #  end
  #
  #  it "raise error if there is already an existing authorized transaction" do
  #    @order.state = "confirm"
  #    t = Factory(:ccavenue_authorized_transaction)
  #    t.order = @order
  #    t.save!
  #    @order.ccavenue_transactions.reload
  #    @order.save!
  #    get :show, { :order_id => @order.number, :payment_method_id => @payment_method.id, :use_route => :spree }
  #    flash[:error].should_not be_nil
  #  end
  #
  #  it "raise error if the payment method is not Spree::Ccavenue::PaymentMethod" do
  #    @order.state = "confirm"
  #    @order.payments.create!(:payment_method_id => @payment_method.id, :amount => @order.total)
  #    pm = Spree::PaymentMethod::Check.create!
  #    get :show, { :order_id => @order.number, :payment_method_id => pm.id, :use_route => :spree }
  #    flash[:error].should_not be_nil
  #  end
  #
  #  it "cancel existing ccavenue payments" do
  #    @order.state = "confirm"
  #    @order.payments.create!(:payment_method_id => @payment_method.id, :amount => @order.total)
  #    t = Factory(:ccavenue_transaction)
  #    t.order = @order
  #    t.transact
  #    t.save!
  #    t = Factory(:ccavenue_transaction)
  #    t.order = @order
  #    t.transact
  #    t.save!
  #    @order.save!
  #
  #    @order.ccavenue_transactions.reload
  #    get :show, { :order_id => @order.number, :payment_method_id => @payment_method.id, :use_route => :spree }
  #    @order.ccavenue_transactions.reload
  #    @order.ccavenue_transactions.size.should == 3
  #    @order.ccavenue_transactions.select{|ct| ct.canceled? }.size.should == 2
  #    @order.ccavenue_transactions.select{|ct| ct.sent? }.size.should == 1
  #  end
  #end

  context 'callback' do
    before(:each) do
      @request.env["devise.mapping"] = Devise.mappings[:user]
      user = FactoryGirl.create(:user)
      sign_in user

      @order = FactoryGirl.create(:order_with_totals)
      @order.state = 'confirm'
      @order.payments.create!(:payment_method_id => @payment_method.id, :amount => @order.total)
      @order.save!
      @transaction = @order.ccavenue_transactions.create!(:payment_method_id => @payment_method.id, :amount => @order.total)
      @transaction.transact
      @order.save!
    end

    it 'should complete order' do
      post :callback, ccavenue_params('Success')
      response.should redirect_to(spree.order_path(@order, {:checkout_complete => true}))
    end

    it 'should fail order and redirect to cart page' do
      post :callback, ccavenue_params('Failure')
      response.should redirect_to(spree.edit_order_path(@order))
    end

    it 'should cancel order when status Aborted' do
      params = ccavenue_params('Aborted')
      post :callback, params
      response.should redirect_to(spree.edit_order_path(@order))
    end
  end
end

def ccavenue_params(auth_desc)
  params = {}
  params['order_status'] = auth_desc
  params['order_id'] = 'CCAV123456'
  params['amount'] = @order.amount.to_s
  params['card_name'] = 'NETBANKING'
  params[:use_route] = :spree
  params[:id] = @transaction.id
  params
end
