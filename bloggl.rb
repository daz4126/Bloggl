require 'sinatra'
require 'data_mapper'

set :title, ENV['title'] ||'Bloggl'
set :author, ENV['author'] ||'@daz4126'
set :url, ENV['url'] ||'http://bloggl.com'
set :value, ENV['value'] || 'akmxuGD5qige'
set :password, ENV['password'] || 'secret'
set :disqus_shortname, ENV['disqus'] ||nil

DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/development.db")

class Post
  include DataMapper::Resource 
  property :id,           Serial
  property :title,        String
  property :slug,         String, :default => Proc.new { |r, p| r.entry.split(/\r\n|\n/).first.downcase.gsub(/\W/,'-').squeeze('-').chomp('-') }
  property :tags,         String
  property :body,         Text
  property :entry,        Text, :required => true
  property :created_at,   DateTime
  property :updated_at,   DateTime    
  before :save do
    post = self.entry.split(/\r\n|\n/)
    self.title = post.slice!(0)
    self.tags = post.slice!(0)
    self.body = post.join("\r\n").strip
  end
  def summary ; self.body[0,200] ; end
  def short_url ; "/" + self.id.to_s ; end
  def long_url ; "/#{self.created_at.year.to_s}/#{self.created_at.month.to_s}/#{self.created_at.day.to_s}/#{self.slug}"; end
end


helpers do
	def admin? ; request.cookies[settings.author] == settings.value ; end
	def protected! ; stop [ 401, 'Not authorized' ] unless admin? ; end
end

not_found { haml :'404' }

get('/styles.css'){ content_type 'text/css', :charset => 'utf-8' ; sass :styles }

get '/' do
  @post,@posts = Post.new,Post.all(:order => [ :created_at.desc ])
  haml :index, :format => :html5
end
post '/' do
  Post.create(:entry => params[:post])
  redirect '/'
end

get '/edit/:id' do
  protected!
  @post = Post.get(params[:id])
  haml :edit, :format => :html5
end

put '/:id' do
  protected!
  if post = Post.get(params[:id]).update(:entry => params[:post])
    status 201
    redirect post.long_url
  else
    status 412
    redirect '/edit/' + params[:id]  
  end
end

get '/delete/:id' do
  protected!
  @post = Post.get(params[:id])
  haml :delete, :format => :html5
end
delete '/:id' do
  protected!
  Post.get(params[:id]).destroy
  redirect '/'  
end

get '/:year/:month/:day/:slug' do
  @post = Post.first(:slug => params[:slug])
  raise error(404) unless @post
  haml :post, :format => :html5
end

get '/tags/:tag' do
  @posts = Post.all(:tags.like => "%#{params[:tag]}%",:order => [ :created_at.desc ])
  haml :list, { :format => :html5, :locals => { :title => "List of posts tagged with #{params[:tag]}" } }
end

get '/archive' do
  @posts = Post.all(:order => [ :created_at.desc ])
  haml :list, { :format => :html5, :locals => { :title => "Archive" } }
end
get '/feed' do
  @posts = Post.all(:order => [ :created_at.desc ], :limit=>10)
  content_type 'application/rss+xml'
  haml :rss, { :layout => false }
end
get '/admin' do
  haml :admin, :format => :html5
end
post '/admin' do
	response.set_cookie(settings.author, settings.value) if params[:password] == settings.password
	redirect '/'
end
get '/logout' do
  response.set_cookie(settings.author, false)
	redirect '/'
end
get '/:id' do
  @post = Post.get(params[:id])
  raise error(404) unless @post
  haml :post, :format => :html5
end
DataMapper.auto_upgrade!
__END__
@@layout
!!! 5
%html
  %head
    %meta(charset="utf-8")
    %title= settings.title
    %link(rel="stylesheet" media="screen, projection" href="/styles.css")
  %body
    %h1 <a href="/">#{settings.title}</a>
    = yield  
@@index
- if admin?
  %form#post(action="/" method="POST")
    %fieldset
      %legend New Post
      = haml :form, :layout => false
    %input(type="submit" value="Create") or <a href='/logout'>logout</a> 
=haml :list, { :format => :html5, :layout => false, :locals => { :title => "Recent Posts" } }
  
@@list
%h2= title || "List of Posts"
- if @posts.any?
  %ol#posts.hfeed
    - @posts.each do |post|
      %li
        %article.hentry{:id => "post-#{post.id}"}
          %header
            %h3 <a href="#{post.long_url}">#{post.title}</a>
          %footer
            %ul.meta
              %li.tags= post.tags.split.inject([]) { |list, tag| list << "<a href=\"/tags/#{tag}\">#{tag}</a>" }.join(" ") if post.tags
              %li.shorturl <a href="#{post.short_url}" title="Short URL">#{post.short_url}</a>
              %li.posted 
                %time{:datetime => post.created_at}
                  #{post[:created_at].strftime("%d")}/#{post[:created_at].strftime("%b")}/#{post[:created_at].strftime("%Y")}
              %li.tweet <a href="http://twitter.com/?status=#{post.title} by #{settings.author}: #{settings.url}#{post.short_url}">Tweet this</a>
          %p.summary
            :markdown
              #{post.summary}... 
- else
  %p No posts!


@@post
%article.hentry
  %header
  - if admin?
    .admin
      %a(href="/edit/#{@post.id}") EDIT
      %a(href="/delete/#{@post.id}") DELETE
  %h2.entry-title= @post.title
  %footer
    %ul.meta
      %li.tags= @post.tags.split.inject([]) { |list, tag| list << "<a href=\"/tags/#{tag}\" rel=\"tag\">#{tag}</a>" }.join(" ") if @post.tags
      %li.shorturl <a href="#{@post.short_url}" title="Short URL">#{@post.short_url}</a>
      %li.posted 
        %time{:datetime => @post.created_at}
          #{@post[:created_at].strftime("%d")}/#{@post[:created_at].strftime("%b")}/#{@post[:created_at].strftime("%Y")}
      %li.tweet <a href="http://twitter.com/?status=#{@post.title} by #{settings.author}: #{settings.url}#{@post.short_url}">Tweet this</a>
%div
  :markdown
    #{@post.body}
    
- if settings.disqus_shortname
  #disqus_thread
  %script(type="text/javascript" src="http://disqus.com/forums/#{settings.disqus_shortname}/embed.js")
  %noscript <a href="http://{settings.disqus_shortname}.disqus.com/?url=ref">View the discussion thread.</a>
  %a.dsq-brlink(href="http://disqus.com")blog comments powered by <span class="logo-disqus">Disqus</span>
@@edit
%form#post(action="/#{@post.id}" method="POST")
  %input(type="hidden" name="_method" value="PUT")
  %fieldset
    %legend Update Post
    = haml :form, :layout => false
  %input(type="submit" value="Update") or <a href='/'>cancel</a>
@@form
%textarea#post(rows="8" name="post")= @post.entry
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
%p Why not have a look at the <a href="/archive">archive</a>?    
@@styles
h2
  color: dodgerblue
  margin: 0
.tags
  color: #999
  font-weight: bold
#post
  width: 60%
  margin: 0 auto
  textarea
    font: 22px/1.5 georgia,sans-serif
    width: 100%
.meta
  margin: 0
  padding: 0
  list-style: none 
