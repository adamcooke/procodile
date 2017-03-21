require 'procodile/app_determination'

describe Procodile::AppDetermination do

  it "should allow root and procfile to be provided" do
    ap = Procodile::AppDetermination.new('/', '/app', 'Procfile', nil)
    expect(ap.root).to eq '/app'
    expect(ap.procfile).to eq '/app/Procfile'
    expect(ap.user).to eq nil
    expect(ap.environment).to eq 'production'
    expect(ap.in_app_directory?).to be false
  end

  it "should allow root to be provided and assume the procfile based on this" do
    ap = Procodile::AppDetermination.new('/', '/app', nil, nil)
    expect(ap.root).to eq '/app'
    expect(ap.procfile).to eq '/app/Procfile'
    expect(ap.user).to eq nil
    expect(ap.environment).to eq 'production'
    expect(ap.in_app_directory?).to be false
  end

  it "should allow the procfile to be provided and assume the root based on this" do
    ap = Procodile::AppDetermination.new('/', nil, '/app/Procfile', nil)
    expect(ap.root).to eq '/app'
    expect(ap.procfile).to eq '/app/Procfile'
    expect(ap.user).to eq nil
    expect(ap.environment).to eq 'production'
    expect(ap.in_app_directory?).to be false
    expect(ap.ambiguous?).to be false
  end

  it "should use the current working directory if it contains a procfile" do
    allow(File).to receive(:file?) do |arg|
      !!(arg =~ /\/tmp\/someapp\/Procfile/)
    end
    ap = Procodile::AppDetermination.new('/tmp/someapp', nil, nil, nil)
    expect(ap.root).to eq '/tmp/someapp'
    expect(ap.procfile).to eq '/tmp/someapp/Procfile'
    expect(ap.user).to eq nil
    expect(ap.environment).to eq 'production'
    expect(ap.in_app_directory?).to be true
    expect(ap.ambiguous?).to be false
  end

  it "should return nothing if there's no global config and no procfile in the pwd" do
    ap = Procodile::AppDetermination.new('/tmp/emptydir', nil, nil, nil)
    expect(ap.root).to eq nil
    expect(ap.procfile).to eq nil
    expect(ap.user).to eq nil
    expect(ap.environment).to eq 'production'
    expect(ap.in_app_directory?).to be false
    expect(ap.ambiguous?).to be true
  end

  it "should always use the provided environment" do
    ap = Procodile::AppDetermination.new('/', '/app', 'Procfile', 'development')
    expect(ap.root).to eq '/app'
    expect(ap.procfile).to eq '/app/Procfile'
    expect(ap.user).to eq nil
    expect(ap.environment).to eq 'development'
    expect(ap.in_app_directory?).to be false
  end

  context "with global options" do
    it "should use root and procfile from the global options if none is provided" do
      ap = Procodile::AppDetermination.new('/', nil, nil, nil, {'root' => '/app', 'procfile' => 'Procfile'})
      expect(ap.root).to eq '/app'
      expect(ap.procfile).to eq '/app/Procfile'
      expect(ap.user).to be_nil
      expect(ap.in_app_directory?).to be false
      expect(ap.ambiguous?).to be false
    end

    it "should use root and procfile from the global options if none is provided" do
      ap = Procodile::AppDetermination.new('/', nil, nil, nil, {'root' => '/app', 'procfile' => 'Procfile', 'user' => 'rails'})
      expect(ap.root).to eq '/app'
      expect(ap.procfile).to eq '/app/Procfile'
      expect(ap.user).to eq 'rails'
      expect(ap.in_app_directory?).to be false
      expect(ap.ambiguous?).to be false
    end

    it "should return the options for a given app from the global options" do
      ap = Procodile::AppDetermination.new('/', nil, nil, nil, [{'root' => '/app', 'procfile' => 'Procfile', 'user' => 'rails'}, {'root' => '/app2', 'procfile' => 'Procfile2', 'user' => 'rails2', 'user_reexec' => true, 'environment' => 'test'}])
      expect(ap.in_app_directory?).to be false
      expect(ap.ambiguous?).to be true
      expect(ap.app_options).to_not be_empty
      expect(ap.app_options[0]).to eq '/app'
      expect(ap.app_options[1]).to eq '/app2'
      ap.set_app(1)
      expect(ap.ambiguous?).to be false
      expect(ap.root).to eq '/app2'
      expect(ap.procfile).to eq '/app2/Procfile2'
      expect(ap.user).to eq 'rails2'
      expect(ap.environment).to eq 'test'
      expect(ap.reexec?).to be true
    end

    it "should use global details for user and environment when in the directory" do
      allow(File).to receive(:file?) do |arg|
        !!(arg =~ /\/app\/Procfile/)
      end
      ap = Procodile::AppDetermination.new('/app', nil, nil, nil, [{'root' => '/app', 'procfile' => 'Procfile', 'user' => 'rails', 'environment' => 'banana'}])
      expect(ap.in_app_directory?).to be true
      expect(ap.user).to eq 'rails'
      expect(ap.environment).to eq 'banana'
    end

  end

end
