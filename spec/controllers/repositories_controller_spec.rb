require 'spec_helper'

describe RepositoriesController do
  before do
    skip_repository_callbacks
    stubs_current_user
    @repository = FactoryGirl.build_stubbed(:repository, github_name: "flyerhzm/rails-brakeman.com", name: "rails-brakeman.com")

    add_ability
  end

  context "GET :new" do
    it "should assign repository" do
      @ability.can :new, Repository
      get :new
      response.should be_ok
      assigns(:repository).should_not be_nil
    end
  end

  context "POST :create" do
    it "should redirect to edit page if create successfully" do
      @ability.can :create, Repository
      controller.stubs(:own_repository?).returns(true)
      controller.stubs(:org_repository?).returns(true)
      post :create, repository: {github_name:"flyerhzm/test"}
      repository = assigns(:repository)
      response.should redirect_to([:edit, repository])
    end

    it "should render new page if create failed" do
      @ability.can :create, Repository
      controller.stubs(:own_repository?).returns(true)
      controller.stubs(:org_repository?).returns(true)
      Repository.any_instance.stubs(:save).returns(false)
      post :create, repository: {github_name:"flyerhzm/test"}
      response.should render_template(:new)
    end

    it "should redirect ot new if user is not owner" do
      @ability.can :create, Repository
      controller.stubs(:own_repository?).returns(false)
      controller.stubs(:org_repository?).returns(false)
      post :create, repository: {github_name:"flyerhzm/test"}
      response.should redirect_to([:new, :repository])
    end
  end

  context "GET :edit" do
    it "should assign repository" do
      @ability.can :edit, Repository
      Repository.expects(:find).with(@repository.id.to_s).returns(@repository)
      get :edit, id: @repository.id
      response.should be_ok
      assigns(:repository).should == @repository
    end
  end

  context "PUT :update" do
    it "should redirecrt to edit page if update successfully" do
      @ability.can :update, Repository
      Repository.expects(:find).with(@repository.id.to_s).returns(@repository)
      @repository.expects(:update_attributes).returns(true)
      put :update, id: @repository.id
      response.should redirect_to([:edit, @repository])
    end

    it "should render edit page if update failed" do
      @ability.can :update, Repository
      Repository.expects(:find).with(@repository.id.to_s).returns(@repository)
      @repository.expects(:update_attributes).returns(false)
      put :update, id: @repository.id
      response.should render_template(:edit)
    end
  end

  context "GET :show" do
    context "without build" do
      it "should redirect with id" do
        Repository.expects(:find).with(@repository.id.to_s).returns(@repository)

        @ability.can :read, Repository
        get :show, id: @repository.id
        response.should redirect_to("/flyerhzm/rails-brakeman.com")
      end

      it "shoud assign repository with owner_name and repository_name" do
        Repository.expects(:where).with(github_name: "flyerhzm/rails-brakeman.com").returns(stub('repositories', first: @repository))
        @repository.expects(:builds).returns(stub('build', last: nil))

        @ability.can :read, Repository
        get :show, owner_name: "flyerhzm", repository_name: "rails-brakeman.com"
        response.should be_ok
        assigns(:repository).should_not be_nil
      end

      it "should render 404 if owner_name or repository_name does not exist" do
        Repository.expects(:where).with(github_name: "flyerhzm/rails-brakeman.com").returns(stub('repositories', first: nil))

        get :show, owner_name: "flyerhzm", repository_name: "rails-brakeman.com"
        response.should be_not_found
        assigns(:repository).should be_nil
      end
    end

    context "with build" do
      it "should assign build" do
        Repository.expects(:where).with(github_name: "flyerhzm/rails-brakeman.com").returns(stub('repositories', first: @repository))
        build = FactoryGirl.build_stubbed(:build)
        @repository.expects(:builds).returns(stub('build', last: build))

        @ability.can :read, Repository
        get :show, owner_name: @user.nickname, repository_name: @repository.name
        response.should render_template("builds/show")
        assigns(:build).should_not be_nil
      end
    end

    context "png" do
      it "should send_file with badge" do
        Repository.expects(:where).with(github_name: "flyerhzm/rails-brakeman.com").returns(stub('repositories', first: @repository))
        build = FactoryGirl.build_stubbed(:build, aasm_state: "completed")
        @repository.expects(:builds).returns(stub('build', last: build))

        controller.expects(:send_file).with(Rails.root.join("public/images/passing.png"), type: 'image/png', disposition: 'inline')
        controller.stubs(:render)

        @ability.can :read, Repository
        get :show, owner_name: @user.nickname, repository_name: @repository.name, format: "png"
      end
    end
  end

  context "POST :sync" do
    let(:hook_json) { File.read(Rails.root.join("spec/fixtures/github_hook.json")) }
    let(:last_message) {
      {
        "id" => "473d12b3ca40a38f12620e31725922a9d88b5386",
        "url" => "https://github.com/railsbp/rails-bestpractices.com/commit/473d12b3ca40a38f12620e31725922a9d88b5386",
        "author" => {
          "email" => "flyerhzm@gmail.com",
          "name" => "Richard Huang"
        },
        "message" => "copy config yaml files for travis",
        "timestamp" => "2011-12-25T20:36:34+08:00"
      }
    }

    it "should generate build" do
      repository = FactoryGirl.build_stubbed(:repository, html_url: "https://github.com/railsbp/rails-bestpractices.com", authentication_token: "123456789")
      Repository.expects(:where).with(html_url: "https://github.com/railsbp/rails-bestpractices.com").returns([repository])
      repository.expects(:generate_build).with("master", last_message)
      post :sync, token: "123456789", payload: hook_json, format: 'json'
      response.should be_ok
      response.body.should == "success"
    end

    it "should not generate build if token is wrong" do
      repository = FactoryGirl.build_stubbed(:repository, html_url: "https://github.com/railsbp/rails-bestpractices.com")
      Repository.expects(:where).with(html_url: "https://github.com/railsbp/rails-bestpractices.com").returns([repository])
      post :sync, token: "123456789", payload: hook_json, format: 'json'
      response.should be_ok
      response.body.should == "not authenticate"
    end

    it "should not generate build if url does not exist" do
      repository = FactoryGirl.build_stubbed(:repository, html_url: "https://github.com/railsbp/rails-bestpractices.com")
      Repository.expects(:where).with(html_url: "https://github.com/railsbp/rails-bestpractices.com").returns([])
      post :sync, token: "123456789", payload: hook_json, format: 'json'
      response.should be_ok
      response.body.should == "not authenticate"
    end

    it "should not generate build if repository is private" do
      repository = FactoryGirl.build_stubbed(:repository, private: true, html_url: "https://github.com/railsbp/rails-bestpractices.com", authentication_token: "123456789")
      Repository.expects(:where).with(html_url: "https://github.com/railsbp/rails-bestpractices.com").returns([repository])
      post :sync, token: "123456789", payload: hook_json, format: 'json'
      response.should be_ok
      response.body.should == "no private repository"
    end

    it "should not generate build if repository is not rails project" do
      repository = FactoryGirl.build_stubbed(:repository, rails: false, html_url: "https://github.com/railsbp/rails-bestpractices.com", authentication_token: "123456789")
      Repository.expects(:where).with(html_url: "https://github.com/railsbp/rails-bestpractices.com").returns([repository])
      post :sync, token: "123456789", payload: hook_json, format: 'json'
      response.should be_ok
      response.body.should == "not rails repository"
    end
  end
end
