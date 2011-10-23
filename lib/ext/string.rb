class String
  def shorten
    if self.size > SHORTEN_LIMIT
      return self[0,SHORTEN_LIMIT] + "..."
    end
    
    return self
  end

  def get_date
    date = DateTime.strptime(self, "%m/%d/%Y %H:%M").in_time_zone("UTC")
    date.zone = Time.zone
    return date
  end
end
