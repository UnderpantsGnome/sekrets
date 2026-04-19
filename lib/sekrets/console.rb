module Sekrets::Console
  def prompt_for(*words)
    ['sekrets:', words, '> '].flatten.compact.join(' ')
  end

  def ask(question)
    print prompt_for(question)
    gets.strip
  end

  def console?
    STDIN.tty?
  end
end
