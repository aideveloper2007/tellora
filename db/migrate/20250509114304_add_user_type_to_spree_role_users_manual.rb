class AddUserTypeToSpreeRoleUsersManual < ActiveRecord::Migration[6.1]
  def up
    unless column_exists?(:spree_role_users, :user_type)
      add_column :spree_role_users, :user_type, :string
      add_index :spree_role_users, :user_type
      
      # Simplified version that should work
      update_sql = "UPDATE spree_role_users SET user_type = 'Spree::User' WHERE user_type IS NULL"
      ActiveRecord::Base.connection.execute(update_sql)
      
      change_column_null :spree_role_users, :user_type, false
    end
  end
  
  def down
    remove_index :spree_role_users, :user_type, if_exists: true
    remove_column :spree_role_users, :user_type, if_exists: true
  end
end