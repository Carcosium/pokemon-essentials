#===============================================================================
#
#===============================================================================
class AnimationPlayer
  attr_accessor :looping
  attr_accessor :slowdown   # 1 = normal speed, 2 = half speed, 3 = one third speed, etc.

  # animation is either a GameData::Animation or a hash made from one.
  # user is a Battler, or nil
  # targets is an array of Battlers, or nil
  def initialize(animation, user, targets, scene)
    @animation = animation
    @user = user
    @targets = targets
    @scene = scene
    @viewport = @scene.viewport
    @sprites = @scene.sprites
    initialize_battler_sprite_names
    initialize_battler_coordinates
    @looping = false
    @slowdown = 1
    @timer_start = nil
    @anim_sprites = []   # Each is a ParticleSprite
    @duration = total_duration
  end

  # Doesn't actually create any sprites; just gathers them into a more useful array
  def initialize_battler_sprite_names
    @battler_sprites = []
    if @user
      pkmn = @user.pokemon
      @battler_sprites[@user.index] = []
      @battler_sprites[@user.index].push(GameData::Species.front_sprite_filename(
          pkmn.species, pkmn.form, pkmn.gender))
      @battler_sprites[@user.index].push(GameData::Species.back_sprite_filename(
        pkmn.species, pkmn.form, pkmn.gender))
    end
    if @targets
      @targets.each do |target|
        pkmn = target.pokemon
        @battler_sprites[target.index] = []
        @battler_sprites[target.index].push(GameData::Species.front_sprite_filename(
            pkmn.species, pkmn.form, pkmn.gender))
        @battler_sprites[target.index].push(GameData::Species.back_sprite_filename(
          pkmn.species, pkmn.form, pkmn.gender))
      end
    end
  end

  def initialize_battler_coordinates
    @user_coords = nil
    if @user
      sprite = @sprites["pokemon_#{@user.index}"]
      @user_coords = [sprite.x, sprite.y - (sprite.bitmap.height / 2)]
    end
    @target_coords = []
    if @targets
      @targets.each do |target|
        sprite = @sprites["pokemon_#{target.index}"]
        @target_coords[target.index] = [sprite.x, sprite.y - (sprite.bitmap.height / 2)]
      end
    end
  end

  def dispose
    @anim_sprites.each { |particle| particle.dispose }
    @anim_sprites.clear
  end

  #-----------------------------------------------------------------------------

  def particles
    return (@animation.is_a?(GameData::Animation)) ? @animation.particles : @animation[:particles]
  end

  # Return value is in seconds.
  def total_duration
    ret = AnimationPlayer::Helper.get_duration(particles) / 20.0
    ret *= slowdown
    return ret
  end

  #-----------------------------------------------------------------------------

  def set_up_particle(particle, target_idx = -1)
    particle_sprite = AnimationPlayer::ParticleSprite.new
    # Get/create a sprite
    sprite = nil
    case particle[:name]
    when "User"
      sprite = @sprites["pokemon_#{@user.index}"]
      particle_sprite.set_as_battler_sprite
    when "Target"
      sprite = @sprites["pokemon_#{target_idx}"]
      particle_sprite.set_as_battler_sprite
    when "SE"
      # Intentionally no sprite created
    else
      sprite = Sprite.new(@viewport)
    end
    particle_sprite.sprite = sprite if sprite
    # Set sprite's graphic and ox/oy
    if sprite
      AnimationPlayer::Helper.set_bitmap_and_origin(particle, sprite, @user&.index, target_idx,
        @battler_sprites[@user&.index || -1], @battler_sprites[target_idx])
      end
    # Calculate x/y/z focus values and additional x/y modifier and pass them all
    # to particle_sprite
    focus_xy = AnimationPlayer::Helper.get_xy_focus(particle, @user&.index, target_idx,
                                                    @user_coords, @target_coords[target_idx])
    offset_xy = AnimationPlayer::Helper.get_xy_offset(particle, sprite)
    focus_z = AnimationPlayer::Helper.get_z_focus(particle, @user&.index, target_idx)
    particle_sprite.focus_xy = focus_xy
    particle_sprite.offset_xy = offset_xy
    particle_sprite.focus_z = focus_z
    # Find earliest command and add a "make visible" command then
    if sprite && !particle_sprite.battler_sprite?
      first_cmd = -1
      particle.each_pair do |property, cmds|
        next if !cmds.is_a?(Array) || cmds.empty?
        cmds.each do |cmd|
          first_cmd = cmd[0] if first_cmd < 0 || first_cmd > cmd[0]
        end
      end
      particle_sprite.add_set_process(:visible, first_cmd * slowdown, true) if first_cmd >= 0
    end
    # Add all commands
    particle.each_pair do |property, cmds|
      next if !cmds.is_a?(Array) || cmds.empty?
      cmds.each do |cmd|
        if cmd[1] == 0
          if sprite
            particle_sprite.add_set_process(property, cmd[0] * slowdown, cmd[2])
          else
            # SE particle
            filename = nil
            case property
            when :user_cry
              filename = GameData::Species.cry_filename_from_pokemon(@user.pokemon) if @user
            when :target_cry
              # NOTE: If there are multiple targets, only the first one's cry
              #       will be played.
              if @targets && !@targets.empty?
                filename = GameData::Species.cry_filename_from_pokemon(@targets.first.pokemon)
              end
            else
              filename = "Anim/" + cmd[2]
            end
            particle_sprite.add_set_process(property, cmd[0] * slowdown, [filename, cmd[3], cmd[4]]) if filename
          end
        else
          particle_sprite.add_move_process(property, cmd[0] * slowdown, cmd[1] * slowdown, cmd[2], cmd[3] || :linear)
        end
      end
    end
    # Finish up
    @anim_sprites.push(particle_sprite)
  end

  # Creates sprites and ParticleSprites, and sets sprite properties that won't
  # change during the animation.
  def set_up
    particles.each do |particle|
      if GameData::Animation::FOCUS_TYPES_WITH_TARGET.include?(particle[:focus]) && @targets
        one_per_side = [:target_side_foreground, :target_side_background].include?(particle[:focus])
        sides_covered = []
        @targets.each do |target|
          next if one_per_side && sides_covered.include?(target.index % 2)
          set_up_particle(particle, target.index)
          sides_covered.push(target.index % 2)
        end
      else
        set_up_particle(particle)
      end
    end
    reset_anim_sprites
  end

  # Sets the initial properties of all sprites, and marks all processes as not
  # yet started.
  def reset_anim_sprites
    @anim_sprites.each { |particle| particle.reset_processes }
  end

  #-----------------------------------------------------------------------------

  def start
    @timer_start = System.uptime
  end

  def playing?
    return !@timer_start.nil?
  end

  def finish
    @timer_start = nil
    @finished = true
  end

  def finished?
    return @finished
  end

  def can_continue_battle?
    return finished?
  end

  #-----------------------------------------------------------------------------

  def update
    return if !playing?
    if @need_reset
      reset_anim_sprites
      start
      @need_reset = false
    end
    time_now = System.uptime
    elapsed = time_now - @timer_start
    # Update all particles/sprites
    @anim_sprites.each { |particle| particle.update(elapsed) }
    # Finish or loop the animation
    if elapsed >= @duration
      if looping
        @need_reset = true
      else
        finish
      end
    end
  end
end