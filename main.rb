module OrderedJob
  Error = Class.new StandardError
  SelfReferentialJob = Class.new Error
  CircularReference = Class.new Error

  def dependency_tree_for job_lines
    return "" if !job_lines || job_lines == "" || job_lines == "\n"

    changed_deps = false

    job_lines.split("\n").map do |job|
      n, d = job.scan(/(\w+) =>(?: (\w+))?/).first
      d = Array(d)
      a = [n, d].instance_eval do
        alias :name :first
        alias :deps :last
        self
      end
    end.
    
    each do |job|
      raise SelfReferentialJob if job.deps.include?(job.name)
    end.

    # MAAAAAAAAAAAAAAASIVE hack to figure out circular deps.
    # Basically just recurse and catch the Stack Error when we
    # hit circular deps.
    instance_eval do
      all_depends_for = lambda do |job|
        job.deps.map do |dep|
          j = self.find {|j| j.name == dep }
          all_depends_for[j] if j.deps
          j.flatten
        end
      end

      each do |job|
        begin
          new_deps = all_depends_for[job].flatten || []
          unless job.deps == new_deps
            changed_deps = true
            job[1] = new_deps
          end
          job.deps
        rescue SystemStackError
          raise CircularReference
        end
        
      end

      self
    end.
    # Magic
    reverse.
    sort do |a ,b|
      a.deps.include?(b.name) ? 1 : a.name <=> b.name
    end.

    # More Magic
    instance_eval do
      changed_deps ? reverse : self
    end.
    sort do |a ,b|
      a.deps.include?(b.name) ? 1 : a.name <=> b.name
    end.

    map(&:name).

    join("\n")
  end

end

if $0 == __FILE__
  require "testrocket"
  include OrderedJob

  empty = dependency_tree_for ""
  +-> { empty == "" }


  empty_newline = dependency_tree_for "
"
  +-> { empty_newline == "" }


  one_job = dependency_tree_for "a =>
"
  +-> { one_job.split("\n") == %w(a) }


  multiple_jobs_no_deps = dependency_tree_for "a =>
b =>
c =>
"
  +-> { multiple_jobs_no_deps.split("\n") == %w(a b c) }



  multiple_jobs_one_dep = dependency_tree_for "a =>
  b => c
  c =>
"
  mjod = multiple_jobs_one_dep.split("\n")
  +-> { mjod.index("c") < mjod.index("b") }



  multiple_jobs_multiple_deps = dependency_tree_for "a =>
  b => c
  c => f
  d => a
  e => b
  f =>
"
  mjmd = multiple_jobs_multiple_deps.split("\n")
  +-> { mjmd.index("f") < mjmd.index("c") }
  +-> { mjmd.index("c") < mjmd.index("b") }
  +-> { mjmd.index("b") < mjmd.index("e") }
  +-> { mjmd.index("a") < mjmd.index("d") }



  !-> { "self depending" }
  +-> do
    begin
      dependency_tree_for("a =>
b => b
c =>
")
      false
    rescue OrderedJob::SelfReferentialJob
      true
    end
  end




  +-> do
    begin
      dependency_tree_for "a =>
b => c
c => f
d => a
e =>
f => b
"
      false
    rescue OrderedJob::CircularReference
      true
    end
    
  end

end
