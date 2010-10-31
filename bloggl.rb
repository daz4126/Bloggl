%w[rubygems sinatra dm-core dm-migrations dm-validations dm-timestamps haml sass].each{ |lib| require lib }
DataMapper.setup(:default, ENV['DATABASE_URL'] || "sqlite3://#{Dir.pwd}/development.db")
set :title, ENV['TITLE'] ||'Bloggl'
set :author, ENV['AUTHOR'] ||'@daz4126'
set :url, ENV['URL'] ||'http://bloggl.com'
set :token, ENV['TOKEN'] || 'akmxuGD5qige'
set :password, ENV['PASSWORD'] || 'secret'
set :disqus, ENV['DISQUS'] || nil
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
  def short_url ; "/" + self.id.to_s ; end
  def long_url ; "/#{self.created_at.year.to_s}/#{self.created_at.month.to_s}/#{self.created_at.day.to_s}/#{self.slug}"; end
end
helpers do
	def admin? ; request.cookies[settings.author] == settings.token ; end
	def protected! ; halt [ 401, 'Not authorized' ] unless admin? ; end
end
not_found { haml :'404' }
get('/styles.css'){ content_type 'text/css', :charset => 'utf-8' ; scss :styles }
get('/application.js') { content_type 'text/javascript' ; render :str, :js, :layout => false }
get('/'){ @posts = Post.all(:order => [ :created_at.desc ]) ;   haml :index }
post('/'){ Post.create(:body => params[:post]) ;   redirect '/' }
get('/edit/:id'){ protected! ; @post = Post.get(params[:id]) ; haml :edit }
put '/:id' do
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
get('/delete/:id'){ protected! ; @post = Post.get(params[:id]) ; haml :delete }
delete('/:id'){ protected! ; Post.get(params[:id]).destroy ; redirect '/'  }
get '/:year/:month/:day/:slug' do
  @post = Post.first(:slug => params[:slug])
  raise error(404) unless @post ; haml :post
end
get '/tags/:tag' do
  @posts = Post.all(:tags.like => "%#{params[:tag]}%",:order => [ :created_at.desc ])
  haml :list, :locals => { :title => "List of posts tagged with #{params[:tag]}" }
end
get '/archive' do
  @posts = Post.all(:order => [ :created_at.desc ])
  haml :list, :locals => { :title => "Archive" }
end
get '/feed' do
  @posts = Post.all(:order => [ :created_at.desc ], :limit=>10)
  content_type 'application/rss+xml' ; haml :rss, { :layout => false }
end
get('/admin'){ haml :admin }
post '/admin' do
	response.set_cookie(settings.author, settings.token) if params[:password] == settings.password
	redirect '/'
end
get('/logout'){ response.set_cookie(settings.author, false) ;	redirect '/' }
get('/:id'){ post = Post.get(params[:id]) ; raise error(404) unless post ; redirect post.long_url }
DataMapper.auto_upgrade!
__END__
@@layout
!!! 5
%html
  %head
    %meta(charset="utf-8")
    %title= settings.title
    %link(rel="stylesheet" media="screen, projection" href="/styles.css")
    %script(src="/application.js")
  %body
    %header(role="banner")
      %h1 <a href="/">#{settings.title}</a>
    = yield
    %footer(role="contentinfo")
      %nav
        %ul(role="navigation")
          %li <a href="/archive" rel="archives">archive</a>
          %li <a href="/feed">RSS Feed</a>
      %small &copy; Copyright #{settings.author} #{Time.now.year}. All Rights Reserved.
    - if settings.disqus
      %script var disqus_shortname = 'bloggl';(function () {var s = document.createElement('script'); s.async = true;s.src = 'http://disqus.com/forums/bloggl/count.js';(document.getElementsByTagName('HEAD')[0] || document.getElementsByTagName('BODY')[0]).appendChild(s);}());

@@index
- if admin?
  %p.logout You are logged in as #{settings.author} (<a href='/logout'>logout</a>)
  %form#post(action="/" method="POST")
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
  %script(type="text/javascript" src="http://disqus.com/forums/#{settings.disqus}/embed.js")
  %noscript <a href="http://{settings.disqus}.disqus.com/?url=ref">View Comments</a>
  %a.dsq-brlink(href="http://disqus.com")blog comments powered by <span class="logo-disqus">Disqus</span>
  
@@article
%header
  - if admin?
    .admin
      %a(href="/edit/#{post.id}") EDIT
      %a(href="/delete/#{post.id}") DELETE
  %h1.entry-title= post.title
%footer
  %ul.post-info
    %li.tags= post.tags.split.inject([]) { |list, tag| list << "<a href=\"/tags/#{tag}\" rel=\"tag\">#{tag}</a>" }.join(" ") if post.tags
    %li.shorturl(rel="bookmark") <a href="#{post.short_url}" title="Short URL">#{settings.url}#{post.short_url}</a>
    %li.posted 
      %time{:datetime => post.created_at}
        #{post[:created_at].strftime("%d")}/#{post[:created_at].strftime("%b")}/#{post[:created_at].strftime("%Y")}
    %li.tweet <a href="http://twitter.com/?status=#{post.title} by #{settings.author}: #{settings.url}#{post.short_url}">Tweet this</a>
    - if settings.disqus
      %li.comments <a href="#{ post.long_url }#disqus_thread">comments</a>
  
@@edit
%form#post(action="/#{@post.id}" method="POST")
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
%p Why not have a look at the <a href="/archive" rel="archives">archive</a>?

@@js

@@styles
@import url("http://fonts.googleapis.com/css?family=Droid+Sans+Serif&subset=latin");
$bg: #fff;
$primary: #00c;
$secondary: #fcc;
$color: #666;
$font: "Droid serif",Georgia,"Times New Roman",serif;
$hcolor: $primary;
$hfont: 'Droid Sans', helvetica, arial, serif;
$hbold: false;
$acolor:$primary;
$ahover:$secondary;
$avisited:lighten($acolor,10%);

html, body, div, span, object, iframe,h1, h2, h3, h4, h5, h6, p, blockquote, pre,abbr, address, cite, code,del, dfn, em, img, ins, kbd, q, samp,small, strong, sub, sup, var,b, i,dl, dt, dd, ol, ul, li,fieldset, form, label, legend,table, caption, tbody, tfoot, thead, tr, th, td,article, aside, canvas, details, figcaption, figure, footer, header, hgroup, menu, nav, section, summary,time, mark, audio, video{ margin: 0;padding: 0;border: 0;outline: 0;font-size: 100%;vertical-align: baseline;background: transparent; }
article,aside,canvas,details,figcaption,figure,
footer,header,hgroup,menu,nav,section,summary{ display: block; }
body{ font-family: $font;background-color: $bg;color: $color; }
h1,h2,h3,h4,h5,h6{ color: $hcolor;font-family: $hfont;@if $hbold { font-weight: bold; } @else {font-weight: normal;}}
h1{font-size:4.2em;}h2{font-size:3em;}h3{font-size:2.4em;}
h4{font-size:1.6em;}h5{font-size:1.2em;}h6{font-size:1em;}
p{font-size:1.2em;line-height:1.5;margin:1em 0;max-width:40em;}
li{font-size:1.2em;line-height:2;}
a,a:link{color:$acolor;}
a:visited{color:$avisited;}
a:hover{color:$ahover;}
img{max-width:100%;_width:100%;display:block;}

article{
  font-size: 12px;
  h1{
    text-transform: uppercase;
    a, a:visited{
    text-decoration: none;}}}
.tags, .tweet{
  a,a:visited{
    color: #fff;
    background: #999;
    padding: 0 4px;
    border-radius: 6px;
    font-weight: bold;
    text-decoration: none;
    &:hover{background: #666;}}}
.shorturl{
  clear: left;
  a, a:visited{
    color: #999;}}
article footer{
  font: 10px/1.6 verdana,sans-serif;
  text-transform: uppercase;
  overflow: hidden;
  ul li{float: left;margin-right: 5px;}}
#post{
  width: 60%;
  margin: 0 auto;
  textarea{
    font: 18px/1.2 georgia,sans-serif;
    width: 100%;}}
.post-info{list-style: none;}
