require File.dirname(__FILE__) + '/../test_helper'

class ArticleTest < Test::Unit::TestCase

  fixtures :environments

  def setup
    @profile = create_user('testing').person
  end
  attr_reader :profile

  should 'have and require an associated profile' do
    a = Article.new
    a.valid?
    assert a.errors.invalid?(:profile_id)

    a.profile = profile
    a.valid?
    assert !a.errors.invalid?(:profile_id)
  end

  should 'require values for name, slug and path' do
    a = Article.new
    a.valid?
    assert a.errors.invalid?(:name)
    assert a.errors.invalid?(:slug)
    assert a.errors.invalid?(:path)

    a.name = 'my article'
    a.valid?
    assert !a.errors.invalid?(:name)
    assert !a.errors.invalid?(:name)
    assert !a.errors.invalid?(:path)
  end

  should 'act as versioned' do
    a = Article.create!(:name => 'my article', :body => 'my text', :profile_id => profile.id)
    assert_equal 1, a.versions(true).size
    a.name = 'some other name'
    a.save!
    assert_equal 2, a.versions(true).size
  end

  should 'act as taggable' do
    a = Article.create!(:name => 'my article', :profile_id => profile.id)
    a.tag_list = ['one', 'two']
    tags = a.tag_list.names
    assert tags.include?('one')
    assert tags.include?('two')
  end

  should 'act as filesystem' do
    a = Article.create!(:name => 'my article', :profile_id => profile.id)
    b = a.children.build(:name => 'child article', :profile_id => profile.id)
    b.save!
    assert_equal 'my-article/child-article', b.path

    a.name = 'another name'
    a.save!

    assert_equal 'another-name/child-article', Article.find(b.id).path
  end

  should 'provide HTML version' do
    profile = create_user('testinguser').person
    a = Article.create!(:name => 'my article', :profile_id => profile.id)
    a.expects(:body).returns('the body of the article')
    assert_equal 'the body of the article', a.to_html
  end

  should 'inform the icon to be used' do
    assert_equal 'text-html', Article.new.icon_name
  end

  should 'provide a (translatable) description' do
    result = 'the description'

    a = Article.new
    a.expects(:_).returns(result)
    assert_same result, a.mime_type_description
  end

  should 'not accept articles with same slug under the same level' do

    # top level articles first
    profile = create_user('testinguser').person
    a1 = profile.articles.build(:name => 'test')
    a1.save!

    # cannot add another top level article with same slug
    a2 = profile.articles.build(:name => 'test')
    a2.valid?
    assert a2.errors.invalid?(:slug)

    # now create a child of a1
    a3 = profile.articles.build(:name => 'test')
    a3.parent = a1
    a3.valid?
    assert !a3.errors.invalid?(:slug)
    a3.save!

    # cannot add another child of a1 with same slug
    a4 = profile.articles.build(:name => 'test')
    a4.parent = a1
    a4.valid?
    assert a4.errors.invalid?(:slug)
  end

  should 'calculate public path' do
    # top level
    a = profile.articles.build(:name => 'aaa')
    a.save!
    assert_equal "/#{profile.identifier}/aaa", a.public_path

    # child articles
    b = profile.articles.build(:name => 'bbb')
    b.parent = a
    b.save!
    assert_equal "/#{profile.identifier}/aaa/bbb", b.public_path
  end

  should 'record who did the last change' do
    a = profile.articles.build(:name => 'test')

    # must be a person
    assert_raise ActiveRecord::AssociationTypeMismatch do
      a.last_changed_by = Profile.new
    end
    assert_nothing_raised do
      a.last_changed_by = Person.new
      a.save!
    end
  end

  should 'search for recent documents for a given profile' do
    first = profile.articles.build(:name => 'first'); first.save!
    second = profile.articles.build(:name => 'second'); second.save!
    third = profile.articles.build(:name => 'third'); third.save!
    forth = profile.articles.build(:name => 'forth'); forth.save!
    fifth = profile.articles.build(:name => 'fifth'); fifth.save!
    
    assert_equal [first,second,third], Article.recent(profile, 3)
    
    assert_equal [first,second,third,forth,fifth], Article.recent(profile, 10)
    
  end

  should 'provied proper descriptions' do
    assert_equal "Article", Article.short_description
    assert_equal "An ordinary article", Article.description
  end

  should 'provide a usable descriptions to subclasses that don\'t override them' do
    klass = Class.new(Article)
    klass.stubs(:name).returns("MyClass")
    klass.expects(:_).with('"%s" article').returns('"%s" article')
    klass.expects(:_).with('An article of type "%s"').returns('An article of type "%s"')

    assert_equal '"MyClass" article', klass.short_description
    assert_equal 'An article of type "MyClass"', klass.description
  end

  should 'indicate wheter children articles are allowed or not' do
    assert_equal true, Article.new.allow_children?
  end

  should 'provide a url to itself' do
    article = profile.articles.build(:name => 'myarticle')
    article.save!

    assert_equal(profile.url + "/myarticle", article.url)
  end

end
