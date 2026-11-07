# The network: every X account the capture has seen, who follows whom, who interacted with whom, and what each
# post's public counts were when it was seen. People stay the owner's curated records; accounts are the directory.
class CreateNetworkCapture < ActiveRecord::Migration[8.1]
  def change
    create_table :x_accounts do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :x_id, null: false
      t.string :handle, null: false
      t.string :name, null: false
      t.text :description
      t.string :avatar_url
      t.integer :followers_count
      t.integer :following_count
      t.integer :posts_count
      t.boolean :verified, null: false, default: false
      t.datetime :observed_at, null: false
      t.timestamps
      t.index %i[workspace_id x_id], unique: true
      t.index %i[workspace_id handle]
    end

    change_table :x_source_posts do |t|
      t.string :quoted_x_id
      t.string :reposted_x_id
      t.integer :like_count
      t.integer :repost_count
      t.integer :quote_count
      t.integer :bookmark_count
      t.integer :view_count
      t.string :media_kinds
      t.boolean :has_link, null: false, default: false
      t.datetime :metrics_observed_at
      t.datetime :first_seen_at
      t.index %i[workspace_id author_x_id published_at]
      t.index %i[workspace_id published_at]
      t.index %i[workspace_id reply_to_x_id]
      t.index %i[workspace_id quoted_x_id]
    end

    # Public counts each time a post was seen, at most one row per post, surface, and hour. The surface says
    # where it was seen: home, search, profile, thread, list, likes, or bookmarks.
    create_table :x_post_observations do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :post_x_id, null: false
      t.string :surface, null: false
      t.datetime :observed_at, null: false
      t.integer :reply_count
      t.integer :like_count
      t.integer :repost_count
      t.integer :quote_count
      t.integer :bookmark_count
      t.integer :view_count
      t.index %i[workspace_id post_x_id observed_at]
      t.index %i[workspace_id surface observed_at]
    end

    # Directed interactions between accounts: reply, quote, repost, mention, or like. post_x_id is the post that
    # carries the interaction (for a like, the liked post); target_post_x_id is the post replied to, quoted,
    # reposted, or liked. Someone else's likes are only visible on the owner's own posts.
    create_table :x_interactions do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :source_x_id, null: false
      t.string :target_x_id, null: false
      t.string :post_x_id, null: false
      t.string :target_post_x_id
      t.datetime :occurred_at
      t.datetime :observed_at, null: false
      t.index %i[workspace_id kind post_x_id source_x_id target_x_id], unique: true, name: "index_x_interactions_uniqueness"
      t.index %i[workspace_id source_x_id target_x_id]
      t.index %i[workspace_id target_x_id]
    end

    # Follow edges seen on follow lists. Partial by nature: a list is only what was scrolled.
    create_table :x_follows do |t|
      t.references :workspace, null: false, foreign_key: true
      t.string :follower_x_id, null: false
      t.string :followed_x_id, null: false
      t.string :seen_on, null: false
      t.datetime :first_seen_at, null: false
      t.datetime :last_seen_at, null: false
      t.index %i[workspace_id follower_x_id followed_x_id], unique: true
      t.index %i[workspace_id followed_x_id]
    end
  end
end
