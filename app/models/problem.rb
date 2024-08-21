class Problem < ActiveRecord::Base
  include ActiveModel::ForbiddenAttributesProtection

  has_many :problem_set_associations, class_name: ProblemSetProblem, inverse_of: :problem, dependent: :destroy
  has_many :problem_sets, through: :problem_set_associations

  has_many :test_sets, -> { rank(:problem_order) }, inverse_of: :problem, dependent: :destroy
  has_many :prerequisite_sets, -> { where(:prerequisite => true).rank(:problem_order) }, :class_name => TestSet
  has_many :test_cases, -> { rank(:problem_order) }, inverse_of: :problem, dependent: :destroy
  has_many :sample_cases, -> { where(:sample => true).rank(:problem_order) }, :class_name => TestCase
  has_many :submissions, :dependent => :destroy
  has_many :test_submissions, -> { where.not(:classification => [Submission::CLASSIFICATION[:ranked], Submission::CLASSIFICATION[:unranked]]).order(:evaluation) }, class_name: Submission

  has_many :user_problem_relations, dependent: :destroy

  belongs_to :owner, :class_name => :User
  belongs_to :evaluator

  has_many :contests, :through => :problem_sets
  has_many :contest_relations, :through => :contests
  has_many :groups, -> { uniq } , :through => :problem_sets
  has_many :group_memberships, :through => :groups, :source => :memberships

  has_many :filelinks, -> { includes(:file_attachment) } , :as => :root, :dependent => :destroy

  validates :name, :presence => true

  before_save do
    self.input = 'data.in' if self.input == ''
    self.output = 'data.out' if self.output == ''
    self.rejudge_at = Time.now if rejudge_at.nil? || (self.changed & %w[memory_limit time_limit evaluator_id]).any?
  end

  after_save do
    if self.rejudge_at_changed? && self.submissions.any?
      job = RejudgeProblemWorker.rejudge(self)
    end
  end

  # Scopes

  scope :score_by_user, ->(user_id) {
    select("problems.*, (SELECT MAX(submissions.score) FROM submissions WHERE submissions.problem_id = problems.id AND submissions.user_id = #{user_id.to_i}) AS score")
  }

  scope :by_group, ->(group_id) { joins(:problem_sets => :groups).where(:groups => {:id => group_id}).distinct }

  # methods

  def recalculate_tests_and_save!
    self.test_error_count = submissions.count(:test_errors)
    self.test_warning_count = submissions.count(:test_warnings)
    self.test_status = case
    when !test_submissions.any?; 0
    when test_error_count > 0; -1
    when test_warning_count > 0; -2
    when !test_submissions.where(:classification => [Submission::CLASSIFICATION[:model],Submission::CLASSIFICATION[:solution]]).any?
      1
    when !test_submissions.where(:classification => Submission::CLASSIFICATION[:incorrect]).any?
      2
    else; 3
    end
    self.save
  end

  def submission_history(user, from = DateTime.new(1), to = DateTime.now)
    return Submission.where("created_at between ? and ? and user_id IN (?) and problem_id = ?", from, to, user, self).order(created_at: :asc)
  end

  def input_type=(type)
    if type == 'stdin'
      self.input = nil
    elsif type == 'file' && self.input == nil
      self.input = ''
    end
  end

  def input_type
    input.nil? ? 'stdin' : 'file'
  end

  def output_type=(type)
    if type == 'stdout'
      self.output = nil
    elsif type == 'file' && self.output == nil
      self.output = ''
    end
  end

  def output_type
    output.nil? ? 'stdout' : 'file'
  end

  # only used when properly joined with submission and problem_set_problems
  def weighted_score
    return nil if self.points.nil?
    self.points * self.weighting / self.maximum_points
  end

  def score_problem_submissions(submissions, weighting)
    if submissions.count == 0
      return nil, nil, nil
    end

    testsets = self.test_sets;
    max_score_per_test_set = {};
    test_set_values = {};

    max_points = 0;
    testsets.each do |x|
      max_score_per_test_set[x.id] = 0;
      test_set_values[x.id] = x.points;
      max_points += x.points;
    end

    curr_subtask_score = 0;
    curr_score = 0;
    best_submission = nil;
    attempt = 1;

    submissions.each_with_index do |submission, idx|
      if submission.points > curr_score
        best_submission = submission;
        curr_score = submission.points;
        attempt = idx + 1;
      end
      
      submission.judge_data.test_sets.each do |(test_set_id, set_data)|
        if test_set_values.has_key?(test_set_id)
          score_from_test_set = test_set_values[test_set_id] * set_data.evaluation;
          if score_from_test_set > max_score_per_test_set[test_set_id]
            curr_subtask_score += score_from_test_set - max_score_per_test_set[test_set_id];
            max_score_per_test_set[test_set_id] = score_from_test_set;
          end
        end
      end

      if curr_subtask_score > curr_score
        curr_score = curr_subtask_score;
        attempt = idx + 1;
      end
    end

    score = (max_points == 0) ? nil : (curr_score * weighting / max_points).to_i;
    return score, attempt, best_submission
  end
end
