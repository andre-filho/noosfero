require_dependency 'region'

Region.class_eval do
  # Use count_without_distinct
  scope :pg_search_plugin_profiles_facets, -> scope {
    joins(:profiles).
    where('profiles.id' => scope.map(&:id)).
    where('categories_profiles.virtual' => false).
    group('categories.id')
  }

  scope :pg_search_plugin_articles_facets, -> scope {
    joins(:articles).
    where('articles.id' => scope.map(&:id)).
    where('articles_categories.virtual' => false).
    group('categories.id')
  }
end
