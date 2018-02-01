module EventsHelper

  include DatesHelper
  include ActionView::Helpers::OutputSafetyHelper

  def list_events(date, events, display_day=false)
    if display_day
      empty_msg = _('No events for this day')
      title = _('Events for %s') % show_date(date)
    else
      empty_msg = _('No events for this month')
      title = _('Events for %s') % show_month(date.year, date.month)
    end

    user_events = events.select { |item| item.display_to?(user) }
    events_for_month = safe_join(user_events.map {|item| display_event_in_listing(item)}, '')
    content_tag('h2', title) +
    content_tag('div',
      (events.any? ?
        content_tag('table', events_for_month) :
          content_tag('em', empty_msg, :class => 'no-events')
      ), :id => 'agenda-items'
    )
  end

  def display_event_in_listing(article)
    content_tag( 'tr',
      content_tag('td',
        content_tag('div', show_time(article.start_date) + ( article.end_date.nil? ?  '' : (_(" to ") + show_time(article.end_date))),:class => 'event-date' ) +
        content_tag('div',link_to(article.title,article.url),:class => 'event-title') +
        content_tag('div',(article.address.nil? or article.address == '')  ? '' : (_('Place: ') + article.address),:class => 'event-place')
      )
    )
  end

  def populate_calendar(selected_date, events)
    selected_date = selected_date.to_date
    events = events.reject{ |event| !event.display_to? user }
    calendar = Event.date_range(selected_date.year, selected_date.month).map do |date|
      [
        # the day itself
        date,
        # is there any events in this date?
        events.any? {|event| event.date_range.cover?(date)},
        # is this date in the current month?
        true
      ]
    end
    # pad with days before
    while calendar.first.first.wday != 0
      calendar.unshift([calendar.first.first - 1.day, false, false])
    end

    # pad with days after (until Saturday)
    while calendar.last.first.wday != 6
      calendar << [calendar.last.first + 1.day, false, false]
    end
    calendar
  end

end
