class Guest
  def initialize(name)
    @name=name
    @autostart=false
    # stow away the vagrant handle and the input guest config
    @vb_callbacks = []
    @lv_callbacks = []
    @callbacks = []

  end

  def define(globalvagrant)
    globalvagrant.vm.define @name, autostart: @autostart do |vagrant|
      vagrant.vm.hostname = @name.gsub(/\//,'-')
      vagrant.vm.synced_folder ".", "/vagrant", disabled: true
      if @provider=='virtualbox'
        vagrant.vm.provider "virtualbox" do |vbox|
          vbox.check_guest_additions = false
          vbox.name = @name.gsub(/\//,'-')

          vbox.customize ["modifyvm", :id, "--clipboard-mode", "bidirectional"]
          vbox.customize ["modifyvm", :id, "--ioapic", "on"]
          vbox.customize ["modifyvm", :id, "--natdnshostresolver1", "on"]
          @vb_callbacks.each do |cb|
            cb.call(vbox)
          end
        end
      elsif @provider=='libvirt'
        libvirt.socket='/run/libvirt/libvirt-sock'
        @lv_callbacks.each do |cb|
          cb.call(libvirt)
        end
      end
      @callbacks.each do |cb|
        cb.call(vagrant)
      end
    end
  end

  def vb(&cb)
    @vb_callbacks.push(cb)
  end

  def lv(&cb)
    @lv_callbacks.push(cb)
  end

  def callback(&cb)
    @callbacks.push(cb)
  end

  def run_inline(name, command)
    callback() do |cb|
      cb.vm.provision "shell", inline: command, env:{"HOME" => @home_path}
    end
  end

  def sync_dir(src,name,owner,group,mode)
    require 'fileutils'
    FileUtils.mkdir_p src
    callback() do |cb|
      cb.vm.synced_folder src, "/#{name}", automount:true, owner:owner, group:group, mount_options:['dmode='+mode,'fmode='+mode]
    end
  end

  def set_box_name(name)
    callback() do |cb|
      cb.vm.box=name
    end
  end
  
  def set_ssh_private_key_path(path)
    callback() do |cb|
      cb.ssh.private_key_path=path
      cb.ssh.keys_only = true
      cb.ssh.insert_key = false
      cb.ssh.dsa_authentication = false
      cb.ssh.verify_host_key = :accept_new_or_local_tunnel
    end
  end

  def set_workspace_dir(workspace_path)
    sync_dir(workspace_path,"workspace",'root','vboxsf','770')
    run_inline("mount workspace","if [ ! -e  $HOME/workspace ]; then ln -f -s /media/sf_workspace $HOME/workspace;  fi")
  end

  def set_box_url(url)
    callback() do |cb|
      cb.vm.box_url=url
    end
  end

  def set_username(username, home_path)
    @home_path=home_path
    callback() do |cb|
      cb.ssh.username=username
    end
  end
  def set_autostart(autostart)
    @autostart=autostart
  end
  def set_cpu_cores(cpus=1)
    vb() do |vbox|
      vbox.customize ["modifyvm", :id, "--cpus", cpus]
    end
    lv() do |libv|
      libv.cpus=cpus
      libv.cpu_model='qemu64'
    end
  end
  def set_provider(provider="virtualbox")
    @provider=provider
  end
  def set_virt_provider(provider='hyperv')
    vb() do |vbox|
      vbox.customize ["modifyvm", :id, "--paravirtprovider", provider]
    end
  end
  def set_nested_virt(enable=false)
    vb() do |vbox|
      vbox.customize ["modifyvm", :id, "--nested-hw-virt", enable ? "on" : "off"]
    end
  end

  def set_memory_MBs(memory=4096)
    vb() do |vbox|
      # vmox.memory = memory
      vbox.customize ["modifyvm", :id, "--memory", memory]
    end
    lv() do |libv|
      libv.memory = memory
    end
  end
  def set_gui(enable=false,vram=96)
    vb() do |vbox|
      vbox.gui = enable
      if enable
        vbox.customize ["modifyvm", :id, "--vram", vram]
      end
    end
  end
  def set_graphics_controller(graphics_controller="vmsvga")
    vb() do |vbox|
      vbox.gui = true
      vbox.customize ["modifyvm", :id, "--graphicscontroller", graphics_controller]
    end
  end
  def set_rdp(enable=false)
    vb() do |vbox|
      vbox.customize ["modifyvm", :id, "--vrdeauthtype", "external"]
      vbox.customize ["modifyvm", :id, "--vrde", enable ? "on" : "off" ] 
    end
  end

  def set_usb(enable=true)
    vb() do |vbox|
      vbox.customize ["modifyvm", :id, "--usb", enable ? "on" : "off"]
      vbox.customize ["modifyvm", :id, "--usbehci", enable ? "on" : "off"]
    end
  end

  def set_networks(networks=[])
    networks.each do |network|
      interface = network.has_key?("interface") ? network['interface'] : "VirtualBox Host-Only Ethernet Adapter"
      ip = network.has_key?("ip") ? network['ip'] : raise("Networks must specify an IP")

      callback() do |cb|
        cb.vm.network "private_network", name: interface,  ip: ip
      end
    end
  end
  def set_shared_folders(folders=[])
    folders.each do |folder|
      sync_dir(folder['src'],folder['name'])
    end
  end

  # def setup_portfwd(portfwd)
  #   host_ip = portfwd.has_key?("host_ip") ? portfwd['host_ip'] : '127.0.0.1'
  #   setup_rdp(@rdp_enable)
  #   vm() do |vmach|
  #     vmach.network "forwarded_port", host: portfwd['host_port'], guest: portfwd['guest_port'], host_ip: host_ip
  #   end
  # end
  # def setup_storage_drives(path, size=10240)
  #   disk_path = "#{@storage_path}/#{@name}/#{path}.vdi"
  #   if !(File.exist?("C:#{disk_path}") )
  #     require 'fileutils'
  #     FileUtils.mkdir_p File.dirname(disk_path)
  #     vb() do |vbox|
  #       vbox.customize ["createmedium", "disk", "--filename", disk_path, "--size", size.to_s]
  #     end
  #   end
  #   vb() do |vbox|
  #     vbox.customize ["storageattach", :id, "--storagectl","IDE Controller","--port","1","--device","1","--type","hdd", "--medium",disk_path]
  #   end
  #   run_provisioner("storage_install.sh")
  # end

end

