# frozen_string_literal: true

# Preset data has a closed vocabulary. A newly added field must either be a
# built-in dispatch field, a mechanism-level field (iso), or have an explicit
# effect reader below. Unknown knobs must fail loudly rather than disappear.
def auditable_preset_rows(presets)
  return [{}, ["PRESETS is not a table"]] unless presets.is_a?(Hash)

  rows = {}
  problems = []
  presets.each do |name, definition|
    if definition.is_a?(Hash)
      rows[name] = definition
    else
      problems << "#{name}: preset definition is not a table"
    end
  rescue StandardError => e
    problems << "#{name}: preset definition cannot be read: #{e.class}: #{e.message}"
  end
  [rows, problems]
rescue StandardError => e
  [{}, ["PRESETS audit raises #{e.class}: #{e.message}"]]
end

def preset_unregistered_keys(preset_data, key_readers)
  return [[:invalid_preset_data, preset_data.class.name]] unless preset_data.is_a?(Hash)

  base_keys = %i[fx stock intensity iso]
  invalid_key_types = preset_data.keys.reject { |key| key.is_a?(Symbol) }
    .map { |key| [:invalid_key_type, key.inspect] }
  unknown = preset_data.keys.select { |key| key.is_a?(Symbol) } - base_keys - key_readers.keys
  unknown + invalid_key_types
end

# Keep checking the remaining probe presets after one renderer raises. A single
# broken chain must not hide later independent failures from the operator.
def preset_smoke_problems(names, probe)
  Array(names).filter_map do |name|
    begin
      out = yield(probe, name)
      "preset #{name} returned nothing for an 8x8 probe" unless out
    rescue StandardError => e
      "preset #{name} raises on an 8x8 probe: #{e.class}: #{e.message}"
    end
  end
end

# Prove that the mandatory final grain changes both a plain preset input
# and a picture that already carries its own grain. Comparing materialised
# pixels catches a silent bypass and a duplicate call that reuses the same
# deterministic grain field instead of adding an independent layer.
def finishing_grain_probe_problems(names, probe)
  presets = Array(names).filter_map do |name|
    data = PRESETS[name.to_sym]
    [name, data] if data
  end
  own_name, own_data = presets.find { |_name, data| Array(data[:fx]).include?("grain") }
  plain_name, = presets.find { |_name, data| !Array(data[:fx]).include?("grain") }
  return ["no preset without an internal grain; finishing-layer probe cannot be verified"] unless plain_name
  return ["no preset with an internal grain; additive-layer probe cannot be verified"] unless own_name

  scenarios = [
    [plain_name, probe],
    [own_name, grain(probe, preset_effective_iso(own_data), own_data[:stock], 0.4)]
  ]
  scenarios.filter_map do |name, before|
    after = yield(before, name)
    if after.write_to_memory == before.write_to_memory
      "finishing grain did not add an independent pixel layer for preset #{name}"
    end
  end
rescue StandardError => e
  ["mandatory finishing-grain probe raises: #{e.class}: #{e.message}"]
end

# A broken H&D table is a finding, not a reason the rest of --vocab-check dies.
# Validate the numeric domain before asking the curve code to evaluate powers or
# divide by the pivot; keep each channel's failure local to its own record.
def hd_curve_problems(name, channel, parameters)
  values = parameters.is_a?(Array) ? parameters : []
  valid_numbers = values.length == 4 && values.all? do |value|
    value.is_a?(Numeric) && value.real? && value.to_f.finite?
  end
  return ["#{name} #{channel}: curve parameters must be four finite real numbers"] unless valid_numbers

  dmin, dmax, pivot, gamma = values
  problems = []
  problems << "#{name} #{channel}: Dmin #{dmin} is not below Dmax #{dmax}" unless dmin < dmax
  problems << "#{name} #{channel}: Dmin #{dmin} is outside [0, 1]" unless dmin >= 0 && dmin <= 1
  problems << "#{name} #{channel}: Dmax #{dmax} is outside [0, 1]" unless dmax >= 0 && dmax <= 1
  problems << "#{name} #{channel}: pivot #{pivot} is outside (Dmin, Dmax)" unless dmin < pivot && pivot < dmax
  problems << "#{name} #{channel}: pivot #{pivot} is outside (0, 1)" unless pivot > 0 && pivot < 1
  problems << "#{name} #{channel}: gamma #{gamma} is not positive" unless gamma > 0
  return problems unless problems.empty?

  drops = HD.channel_curve(values).each_cons(2).count { |a, b| b < a }
  problems << "#{name} #{channel}: curve inverts at #{drops} of 255 steps" if drops.positive?
  problems
rescue StandardError => e
  ["#{name} #{channel}: curve evaluation raises #{e.class}: #{e.message}"]
end

def stock_matrix_audit(name, matrix)
  return { offset: nil, problem: nil } if matrix.nil?

  valid = matrix.is_a?(Array) && matrix.length == 9 && matrix.all? do |value|
    value.is_a?(Numeric) && value.real? && value.to_f.finite?
  end
  return { offset: nil, problem: "#{name}: colour matrix must contain nine finite real numbers" } unless valid

  offset = matrix.each_slice(3).map { |row| (row.sum - 1.0).abs }.max
  { offset:, problem: nil }
rescue StandardError => e
  { offset: nil, problem: "#{name}: colour matrix audit raises #{e.class}: #{e.message}" }
end

def grain_knot_problems(name, knots)
  return [] if knots.nil?

  valid = knots.is_a?(Array) && knots.all? do |value|
    value.is_a?(Numeric) && value.real? && value.to_f.finite?
  end
  return ["#{name} grain_knots must be an array of finite real numbers"] unless valid

  problems = []
  problems << "#{name} grain_knots needs at least two knots" if knots.length < 2
  problems << "#{name} grain_knots go negative" if knots.any?(&:negative?)
  problems
rescue StandardError => e
  ["#{name} grain_knots audit raises #{e.class}: #{e.message}"]
end

def stock_grain_levels(stocks, scale)
  levels = {}
  problems = []
  stocks.each do |name, data|
    unless data.is_a?(Hash)
      problems << "#{name}: stock definition is not a table"
      next
    end

    grain = data[:grain]
    next if grain.nil?
    unless grain.is_a?(Numeric) && grain.real? && grain.to_f.finite? && grain >= 0
      problems << "#{name}: grain must be a finite nonnegative number"
      next
    end

    level = grain * scale
    unless level.to_f.finite?
      problems << "#{name}: scaled grain is not finite"
      next
    end
    levels[name] = level
  rescue StandardError => e
    problems << "#{name}: grain measurement raises #{e.class}: #{e.message}"
  end
  [levels, problems]
end
