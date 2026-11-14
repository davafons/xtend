class PeopleController < ApplicationController
  PER_PAGE = 50
  SORTS = {
    "name" => "people.name COLLATE NOCASE ASC",
    "recent" => "last_reply_at IS NULL, last_reply_at DESC, people.name COLLATE NOCASE ASC",
    "replies" => "reply_total DESC, last_reply_at DESC, people.name COLLATE NOCASE ASC",
    "added" => "people.created_at DESC, people.id DESC",
    "followers" => "people.followers_count IS NULL, people.followers_count DESC, people.name COLLATE NOCASE ASC"
  }.freeze

  def index
    @graph = Follow::Graph.latest
    @people = Person.all
    @people = @people.where("name LIKE ? OR handle LIKE ? OR notes LIKE ? OR description LIKE ?", *Array.new(4, "%#{Person.sanitize_sql_like(params[:q].to_s)}%")) if params[:q].present?
    @people = @people.pinned if params[:filter] == "pinned"
    @people = @people.where(id: Follow::Protection.select(:person_id)) if params[:filter] == "kept"
    @people = @people.where.not(notes: [nil, ""]) if params[:filter] == "notes"
    @people = @people.untagged if params[:filter] == "untagged"
    @people = @people.tagged(params[:tag]) if params[:tag].present?
    @lists = List.ordered.to_a
    @list = @lists.find { _1.id.to_s == params[:list] }
    @people = @people.in_list(@list) if @list
    @talked = date_range_param
    @people = @people.talked_between(@talked.first.in_time_zone..@talked.last.in_time_zone.end_of_day) if @talked
    @tags = Tag.by_use.to_a
    if params[:follow].present?
      if @graph.complete?
        following = @graph.following_ids_query
        followers = @graph.follower_ids_query
        @people = case params[:follow]
        when "mutual" then @people.where(id: following).where(id: followers)
        when "following_only" then @people.where(id: following).where.not(id: followers)
        when "followers_only" then @people.where(id: followers).where.not(id: following)
        when "lost" then @people.where(id: Follow::FollowerPeriod.ended.select(:person_id)).where.not(id: Follow::FollowerPeriod.ongoing.select(:person_id))
        else @people
        end
      else
        @people = @people.none
      end
    end
    if params[:state].present?
      outgoing = ReplyEvent.where(direction: "outgoing").select(:person_id)
      incoming = ReplyEvent.where(direction: "incoming").select(:person_id)
      @people = case params[:state]
      when "Two-way" then @people.where(id: outgoing).where(id: incoming)
      when "You replied only" then @people.where(id: outgoing).where.not(id: incoming)
      when "They replied only" then @people.where(id: incoming).where.not(id: outgoing)
      when "No observed replies" then @people.where.not(id: outgoing).where.not(id: incoming)
      else @people
      end
    end
    @count = @people.count
    @sort = SORTS.key?(params[:sort]) ? params[:sort] : "recent"
    @page = [params[:page].to_i, 1].max
    @people = @people.includes(:pin, :follow_protection, :reply_events, :tags, :lists)
      .select("people.*",
        "(SELECT MAX(occurred_at) FROM reply_events WHERE reply_events.person_id = people.id) AS last_reply_at",
        "(SELECT COUNT(*) FROM reply_events WHERE reply_events.person_id = people.id) AS reply_total")
      .order(Arel.sql(SORTS.fetch(@sort)))
      .offset((@page - 1) * PER_PAGE).limit(PER_PAGE)
    @recent = recent_people if @page == 1 && helpers.people_filter_params.except(:sort).empty?
  end

  # Pinned people first, then whoever you replied with most recently.
  def recent_people
    Person.includes(:pin, :reply_events)
      .select("people.*", "(SELECT MAX(occurred_at) FROM reply_events WHERE reply_events.person_id = people.id) AS last_reply_at")
      .where(id: ReplyEvent.select(:person_id)).or(Person.where(id: Pin.select(:person_id)))
      .order(Arel.sql("(SELECT 1 FROM pins WHERE pins.person_id = people.id) IS NULL, last_reply_at DESC"))
      .limit(4).to_a
  end
  private :recent_people

  def show
    @person = Person.includes(:pin, :follow_protection, :reply_events, :follow_reviews, :follower_periods, :outreach_candidates, :engagements, :tags, :lists).find(params[:id])
    @graph = Follow::Graph.latest
    @timeline = @person.timeline
    @category = Person::Timeline::CATEGORIES.key?(params[:show]) ? params[:show] : nil
    @entries = @timeline.filter(@category)
  end

  def new
    @person = Person.new
  end

  def create
    @person = Person.new(params.require(:person).permit(:handle, :name, :notes))
    if @person.save
      redirect_to @person, notice: "Person saved."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    @person = Person.find(params[:id])
    if @person.update(params.require(:person).permit(:notes))
      redirect_to @person, notice: "Notes saved."
    else
      @graph = Follow::Graph.latest
      @timeline = @person.timeline
      @entries = @timeline.entries
      render :show, status: :unprocessable_entity
    end
  end
end
