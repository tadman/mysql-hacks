class ActiveRecord::Base
  class << self
    remove_const(:VALID_FIND_OPTIONS)

    VALID_FIND_OPTIONS = [
      :conditions, :include, :joins, :limit, :offset,
      :order, :select, :readonly, :group, :from, :lock,
      :index, :count_rows
    ]
  end

  def self.[](id)
    find(id)
  end

protected
  def self.construct_finder_sql(options)
    # Additions: Support for :count_rows, :index
    scope = scope(:find)
    sql  = 'SELECT '
    
    # adding count_rows
    if (options[:count_rows])
      sql << 'SQL_CALC_FOUND_ROWS '
    end
    
    sql << "#{options[:select] || (scope && scope[:select]) || default_select(options[:joins] || (scope && scope[:joins]))} "
    
    sql << "FROM #{(scope && scope[:from]) || options[:from] || quoted_table_name} "
    
    # adding force index
    if ((scope and scope[:index]) || options[:index])
      sql << 'FORCE INDEX ('
      sql << [ (scope and scope[:index]) || options[:index] ].flatten.collect { |i| i.to_s } * ','
      sql << ') '
    end

    add_joins!(sql, options[:joins], scope)
    add_conditions!(sql, options[:conditions], scope)

    add_group!(sql, options[:group], scope)
    add_order!(sql, options[:order], scope)
    add_limit!(sql, options, scope)
    add_lock!(sql, options, scope)

    sql
  end
  
  def self.construct_finder_sql_with_included_associations(options, join_dependency)
    scope = scope(:find)
    sql = 'SELECT '
    
    # Patch for :count_rows
    if (options[:count_rows])
      sql << 'SQL_CALC_FOUND_ROWS '
    end
    
    sql << "#{column_aliases(join_dependency)} FROM #{(scope && scope[:from]) || options[:from] || quoted_table_name} "
    sql << join_dependency.join_associations.collect{|join| join.association_join }.join
    
    # Patch for :index
    if (options[:index])
      sql << 'FORCE INDEX ('
      sql << [ options[:index] ].flatten.collect { |i| i.to_s } * ','
      sql << ') '
    end
    
    add_joins!(sql, options[:joins], scope)
    add_conditions!(sql, options[:conditions], scope)
    add_limited_ids_condition!(sql, options, join_dependency) if !using_limitable_reflections?(join_dependency.reflections) && ((scope && scope[:limit]) || options[:limit])

    add_group!(sql, options[:group], scope)
    add_order!(sql, options[:order], scope)
    add_limit!(sql, options, scope) if using_limitable_reflections?(join_dependency.reflections)
    add_lock!(sql, options, scope)
    
    sanitize_sql(sql)
  end
  
  def self.add_order!(sql, order, scope = :auto)
    order ||= ''
    scope = scope(:find) if :auto == scope
    scoped_order = scope && scope[:order] || ''
    
    order = order.to_s.split(',')
    scoped_order = scoped_order.to_s.split(',')
    
    # magic! aka removing order_by's from original relationship if also 
    # found in scope orders
    order = order.map{|i| i.split(' ')}.reject{|a| scoped_order.map{|b| b.split(' ').first}.member? a.first}.map{|c| c.join(' ')}.join(', ')

    order = [order, scoped_order].reject{|i| i.blank?}.uniq.join(', ')
    
    sql << " ORDER BY #{order}" unless order.blank?
  end

  def self.select_columns(*columns)
    return if (columns.empty?)
    
    scope = scope(:find)
    options = (columns.last.is_a?(Hash) ? columns.pop : { })
    
    sql = 'SELECT '
    sql << columns.collect { |column| "`#{column}`" } * ','
    sql << ' FROM '
    sql << quoted_table_name
    sql << ' '

    add_conditions!(sql, options[:conditions], scope)
    add_order!(sql, options[:order], scope)
    add_limit!(sql, options, scope)
        
    case (columns.length)
    when 1:
      connection.select_values(sanitize_sql(sql))
    else
      connection.select_rows(sanitize_sql(sql))
    end
  end
  
  def self.select(*args)
    self.select_columns(*args)
  end
  
  def self.each(key_column = :id, &block)
    self.select(key_column).each do |key|
      yield(find_by_id(key))
    end
  end

  def self.each_with_index(key_column = :id, &block)
    self.select(:id).each_with_index do |key, i|
      yield(find_by_id(key), i)
    end
  end

  def self.reset!
    connection.execute("DELETE FROM #{table_name}")
    connection.execute("ALTER TABLE #{table_name} AUTO_INCREMENT=1")
  end
  
  def self.import(array)
    array = array.compact
    return if (array.empty?)
    
    columns = array.first.keys
    
    data = array.collect do |row|
      values =columns.collect do |key|
        row[key].to_sql
      end
      
      "(#{values * ','})"
    end
    
    query = "INSERT INTO #{table_name} (#{array[0].keys.collect(&:to_s).collect(&:backquote).join(',')}) VALUES #{data * ','}"
    
    connection.execute(query)
  end
end
