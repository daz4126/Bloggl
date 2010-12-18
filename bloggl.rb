require 'sinatra/base'
class Bloggl < Sinatra::Base
  enable :inline_templates
  %w[dm-core dm-migrations dm-validations dm-timestamps haml sass].each{ |lib| require lib }
  DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/development.db")
  set :title => ENV['TITLE'] ||'Bloggl',:author => ENV['AUTHOR'] ||'daz4126',:url => ENV['URL'] ||'http://bloggl.com',:token => ENV['TOKEN'] || 'makethislong&hardtoguess',:password => ENV['PASSWORD'] || 'secret',:disqus => ENV['DISQUS'] || nil
  set :haml, { :format => :html5 }
  class Post
    include DataMapper::Resource 
    property :id,           Serial
    property :title,        String
    property :slug,         String, :default => Proc.new { |r, p| r.body.split(/\r\n|\n/).first.downcase.gsub(/\W/,'-').squeeze('-').chomp('-') }
    property :tags,         String
    property :body,         Text, :required => true
    property :created_at,   DateTime
    property :updated_at,   DateTime    
    before :save do
      post = self.body.split(/\r\n|\n/)
      self.title = post.slice!(0); self.tags = post.slice!(0)
      self.body = post.join("\r\n").strip
    end
    def summary ; self.body[0,100] ; end
    def short_url ; "/b/" + self.id.to_s ; end
    def long_url ; "/blog/#{self.created_at.year.to_s}/#{self.created_at.month.to_s}/#{self.created_at.day.to_s}/#{self.slug}"; end
  end
  helpers do
	  def admin? ; request.cookies[settings.author] == settings.token ; end
	  def protected! ; halt [ 401, 'Not authorized' ] unless admin? ; end
  end
  not_found { haml :'404' }
  get('/blog'){ @posts = Post.all(:limit => 10,:order => [ :created_at.desc ]) ; haml :index }
  post('/blog'){ Post.create(:body => params[:post]) ; redirect '/blog' }
  get('/blog/edit/:id'){ protected! ; @post = Post.get(params[:id]) ; haml :edit }
  put '/blog/:id' do
    protected!
    @post = Post.get(params[:id])
    if post =@post.update(:body => params[:post])
      status 201
      redirect @post.long_url
    else
      status 400
      haml :edit
    end
  end
  get('/blog/delete/:id'){ protected! ; @post = Post.get(params[:id]) ; haml :delete }
  delete('/blog/:id'){ protected! ; Post.get(params[:id]).destroy ; redirect '/'  }
  get '/blog/:year/:month/:day/:slug' do
    @post = Post.first(:slug => params[:slug])
    @title = @post.title
    raise error(404) unless @post ; haml :post
  end
  get '/blog/tags/:tag' do
    @posts = Post.all(:tags.like => "%#{params[:tag]}%",:order => [ :created_at.desc ])
    haml :list, :locals => { :title => "List of posts tagged with #{params[:tag]}" }
  end
  get '/blog/archive' do
    @posts = Post.all(:order => [ :created_at.desc ])
    haml :list, :locals => { :title => "Archive" }
  end
  get '/blog/feed' do
    @posts = Post.all(:order => [ :created_at.desc ], :limit=>10)
    content_type 'application/rss+xml' ; haml :rss, { :layout => false }
  end
  get('/admin'){ haml :admin }
  post '/admin' do
	  response.set_cookie(settings.author, settings.token) if params[:password] == settings.password
	  redirect '/blog'
  end
  get('/logout'){ response.set_cookie(settings.author, false) ;	redirect '/blog' }
  get('/b/:id'){ post = Post.get(params[:id]) ; raise error(404) unless post ; redirect post.long_url }
end
__END__
@@layout
!!! 5
%html
  %head
    %meta(charset="utf-8")
    %title= @title || settings.title
    %link(rel="stylesheet" media="screen, projection" href="/styles.css")
    %script(src="/application.js")
  %body
    %header(role="banner")
      %h1 <a href="/blog">#{settings.title}</a>
    = yield
    %footer(role="contentinfo")
      %nav
        %ul(role="navigation")
          %li <a href="/archive" rel="archives">archive</a>
          %li <a href="/feed">RSS Feed</a>
      %small &copy; Copyright #{settings.author} #{Time.now.year}. All Rights Reserved.     
      
@@index
- if admin?
  %p.logout You are logged in as #{settings.author} (<a href='/logout'>logout</a>)
  %form#post(action="/blog" method="POST")
    %fieldset
      %legend New Post
      = haml :form
    %input(type="submit" value="Create") 
=haml :list, :locals => { :title => "Recent Posts" }
@@list
%h1= title || "List of Posts"
- if @posts.any?
  %ol#posts.hfeed
    - @posts.each do |post|
      %li
        %article.hentry{:id => "post-#{post.id}"}
          =haml :article, :locals => {:post => post }
          %p.summary
            :markdown
              #{post.summary}... <a href="#{post.long_url}">(read more)</a>
- else
  %p No posts!
@@post
%article(class="hentry entry" id="post-#{@post.id}")
  =haml :article, :locals => {:post => @post }
%section.entry-content
  :markdown
    #{@post.body}  
- if settings.disqus
  #disqus_thread
  %script var disqus_shortname='#{settings.disqus}';var disqus_identifier='#{settings.url+@post.short_url}';var disqus_title='#{@post.title}';var disqus_url='#{settings.url+@post.long_url}';(function () {var dsq = document.createElement('script'); dsq.async = true;dsq.src = 'http://disqus.com/forums/#{settings.disqus}/count.js';(document.getElementsByTagName('HEAD')[0] || document.getElementsByTagName('BODY')[0]).appendChild(dsq);}());
  %noscript <a href="http://#{settings.disqus}.disqus.com/?url=ref">View Comments</a>
  %a.dsq-brlink(href="http://disqus.com")blog comments powered by <span class="logo-disqus">Disqus</span>

@@article
%header
  - if admin?
    .admin
      %a.bloggl_button(href="/edit/#{post.id}") EDIT
      %a.bloggl_button(href="/delete/#{post.id}") DELETE
  %h1.entry-title= post.title
%footer
  %ul.post-info
    %li.tags= post.tags.split.inject([]) { |list, tag| list << "<a href=\"/tags/#{tag}\" rel=\"tag\">#{tag}</a>" }.join(" ") if post.tags
    %li.shorturl(rel="bookmark") <a href="#{post.short_url}" title="Short URL">#{settings.url}#{post.short_url}</a>
    %li.posted 
      %time{:datetime => post.created_at}
        #{post[:created_at].strftime("%d")}/#{post[:created_at].strftime("%b")}/#{post[:created_at].strftime("%Y")}
    %li.tweet <a href="http://twitter.com/?status=#{post.title} by @#{settings.author}: #{settings.url}#{post.short_url}">Tweet this</a>
    - if settings.disqus
      %li.comments <a href="#{ post.long_url }#disqus_thread">comments</a> 
@@edit
%form#post(action="/blog/#{@post.id}" method="POST")
  %input(type="hidden" name="_method" value="PUT")
  %fieldset
    %legend Update Post
    = haml :form, :layout => false
  %input(type="submit" value="Update") or <a href='/'>cancel</a>
@@form
%textarea#post(rows="12" name="post")= (@post.title + "\r\n" + @post.tags + "\r\n\r\n" + @post.body) if @post
@@delete
%h3 Are you sure you want to delete #{@post.title}?
%form(action="//#{@post.id}" method="post")
  %input(type="hidden" name="_method" value="DELETE")
  %input(type="submit" value="Delete") or <a href="/">Cancel</a>  
@@admin
%form(action="/admin" method="post")
  %input(type="password" name="password")
  %input(type="submit" value="Login") or <a href="/">Cancel</a>
@@rss
!!! xml
%feed(xmlns="http://www.w3.org/2005/Atom")
%title= settings.title
%id= settings.url
%updated= @posts.first[:created_at] if @posts.any?
%author
  %name= settings.author
-@posts.each do |post|
  %entry
    %title= post.title
    %link{"rel" => "alternate", "href" => settings.url + "/" + post.id.to_s}
    %id settings.url + "/" + #{post.id.to_s}
    %published= post[:created_at]
    %updated= post[:updated_at]
    %author
      %name= settings.author
    %summary{"type" => "html"}= post.summary
    %content{"type" => "html"}= post.body
@@404
%h3 Sorry, but that page cannot be found
%p Why not have a look at the <a href="/blog/archive" rel="archives">archive</a>?
