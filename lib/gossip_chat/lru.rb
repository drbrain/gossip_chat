class GossipChat::LRU

  include Enumerable

  def initialize size: 20
    @size = size

    @entries = {}
  end

  def << value
    @entries.delete value
    @entries[value] = true
    @entries.delete @entries.first.first if @entries.size > @size
  end

  def each
    return enum_for __method__ unless block_given?

    @entries.keys.each do |entry|
      yield entry
    end
  end

  def to_a
    @entries.keys.to_a
  end

end

