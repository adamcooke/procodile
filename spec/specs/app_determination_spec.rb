require 'procodile/app_determination'

describe Procodile::AppDetermination do

  it "should allow root and procfile to be provided" do
    ap = Procodile::AppDetermination.new('/', '/app', 'Procfile', nil)
    expect(ap.root).to eq '/app'
    expect(ap.procfile).to eq '/app/Procfile'
    expect(ap.in_app_directory?).to be false
  end

  it "should use pwd as root but with no procfile it'll be nil" do
    ap = Procodile::AppDetermination.new('/app', nil, nil)
    expect(ap.root).to eq nil
    expect(ap.procfile).to eq nil
    expect(ap.in_app_directory?).to be false
  end

  it "should have no procfile if only root is provided" do
    ap = Procodile::AppDetermination.new('/home', '/some/app', nil)
    expect(ap.root).to eq "/some/app"
    expect(ap.procfile).to eq nil
    expect(ap.in_app_directory?).to be false
  end

end
