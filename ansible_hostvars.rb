require_relative("./guest.rb")
require("json")
require('open3')


class AnsibleHostvars
  def initialize()
    @group='vagrant_guest'
    @inventories=[]
  end
  def set_inventory(*inventories)
    @inventories=inventories
  end
  def set_group(group)
    @group=group
  end

  def define_vagrant_guest(name,hostvars,globalvagrant)
    prefix = "vagrant_"
    config = hostvars.each_with_object({}) do |(key, value), acc|
      if key.start_with?(prefix)
        new_key = key.sub(prefix, '')
        acc[new_key] = value
      end
    end
    guest = Guest.new(name)
    if config.has_key?("box_name") 
       guest.set_box_name(config['box_name'])
    else
      raise('Must provide box name for '+name)
    end
 
    if config.has_key?("ssh_private_key_path") 
       guest.set_ssh_private_key_path(config['ssh_private_key_path'])
    else
      raise('Must provide ssh private key path for '+name)
    end
    
    if config.has_key?("workspace_path") 
      guest.set_workspace_dir(config['workspace_path'])
    end
    if config.has_key?("box_url") 
      guest.set_box_url(config['box_url'])
    end
    username=config.fetch("username","vagrant")
    guest.set_username(username,config.fetch("home_path","/home/#{username}"))
    guest.set_autostart(config.fetch("autostart",false))
    guest.set_cpu_cores(config.fetch("cpu_cores",1))
    guest.set_virt_provider(config.fetch("virt_provider","virtualbox"))
    guest.set_nested_virt(config.fetch("nested_virt",false))
    guest.set_memory_MBs(config.fetch("memory_MBs",4096))
    guest.set_gui(config.fetch("gui",false),config.fetch("vram_MBs",96))
    guest.set_graphics_controller(config.fetch("graphics_controller","vmsvga"))
    guest.set_rdp(config.fetch("rdp",false))
    guest.set_usb(config.fetch("usb",true))
    guest.set_networks(config.fetch("networks",[]))
    guest.set_shared_folders(config.fetch("shared_folders",[]))

    # install dependencies and do initial configuration
    # guest.run_provisioner("pre_install.sh")
    guest.define(globalvagrant)
    return guest
  end

  def define_vagrant(globalvagrant)
    guest_configs = load()

    guests=[]
    guest_configs.each { |guest_name, guest_config|
      guests.push(define_vagrant_guest(guest_name,guest_config,globalvagrant))
    }

  end
  def load()
    command = [
      'ansible',
      'localhost',
      '-m','copy',
      '-a',"dest=./.vagrant/hostvars.json content={{hostvars | dict2items | selectattr('key', 'in', groups[target_group]) |items2dict| to_nice_json}}",
      '-e','target_group='+@group]
    @inventories.each { |inventory|
      command.push('-i')
      command.push(inventory)
    }


    Open3.popen2(*command) do |stdin, stdout, wait_thr|
      status = wait_thr.value
      if status.success?
        guest_configs=JSON.parse(File.open("./.vagrant/hostvars.json").read())

        return guest_configs      
      else
        raise("Command failed: "+command)
      end
    end
  end

end

