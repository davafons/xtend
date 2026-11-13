class DefaultThemeToDim < ActiveRecord::Migration[8.1]
  def up
    change_column_default :users, :theme, from: "aurora", to: "dim"
    execute "UPDATE users SET theme = 'dim' WHERE theme = 'aurora'"
  end

  def down
    change_column_default :users, :theme, from: "dim", to: "aurora"
  end
end
