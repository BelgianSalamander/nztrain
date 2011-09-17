class Problem < ActiveRecord::Base
  has_many :test_cases
  has_many :submissions
  has_and_belongs_to_many :contests 
  belongs_to :user

  def get_score(user)
    subs = self.submissions.where(:user_id => user)
    scores = subs.map {|s| s.score}
    return scores.max 
  end

end
