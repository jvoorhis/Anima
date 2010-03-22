require 'ffi'
require 'llvm/core'
require 'llvm/execution_engine'
require 'llvm/transforms/scalar'

module Anima
  module C
    extend FFI::Library
    ffi_lib File.join(File.dirname(__FILE__), '../ext/libanima.dylib')
    attach_function :animate, [:pointer, :int, :pointer], :int
  end
  
  module FloatingExpression
    def coerce(obj)
      [Float(obj), self]
    end
    
    def +(rhs)
      FloatingPrimitive.new(:+, self, rhs)
    end
    
    def -(rhs)
      FloatingPrimitive.new(:-, self, rhs)
    end
    
    def *(rhs)
      FloatingPrimitive.new(:*, self, rhs)
    end
    
    def /(rhs)
      FloatingPrimitive.new(:/, self, rhs)
    end
  end
  
  def Float(value)
    case value
    when FloatingExpression then value
    else Anima::FloatingLit[value]
    end
  end
  module_function :Float
  
  class FloatingPrimitive < Struct.new(:op, :lhs, :rhs)
    include FloatingExpression
    
    def initialize(op, lhs, rhs)
      super op, Float(lhs), Float(rhs)
    end
    
    def codegen(builder)
      lvalue = lhs.codegen(builder)
      rvalue = rhs.codegen(builder)
      
      case op
      when :+ then builder.add(lvalue, rvalue)
      when :- then builder.sub(lvalue, rvalue)
      when :* then builder.mul(lvalue, rvalue)
      when :/ then builder.div(lvalue, rvalue)
      end
    end
  end
  
  class FloatingLit < Struct.new(:value)
    include FloatingExpression
    
    def initialize(value)
      super value.to_f
    end
    
    def codegen(builder)
      LLVM::Float(value)
    end
  end
  
  class FloatingData < Struct.new(:data)
    include FloatingExpression
    
    def codegen(builder)
      data
    end
  end
  
  class RGBA < Struct.new(:r, :g, :b, :a)
    def initialize(r,g,b,a)
      super Float(r), Float(g), Float(b), Float(a)
    end
  end
  
  class Point2D < Struct.new(:x, :y)
  end
  
  module_function
  
  def animate!(argv = [])
    mod = LLVM::Module.create("Anima")
    mod.types[:render_callback] = LLVM::Function([LLVM::Int, LLVM::Int, LLVM::Int], LLVM::Int)
    
    mod.functions.add("animate", mod.types[:render_callback]) do |func, buffer, width, height|
      entry = func.basic_blocks.append("entry")
      test  = func.basic_blocks.append("test")
      body  = func.basic_blocks.append("body")
      exit  = func.basic_blocks.append("exit")
      
      index = nil # fwd decl of shared variable
      
      entry.build do |builder|
        index = builder.alloca(LLVM::Int)
        builder.store(LLVM::Int(0), index)
        builder.br(test)
      end
      
      test.build do |builder|
        continue = builder.icmp(:slt,
                     builder.load(index),
                     builder.mul(width, height))
        
        builder.cond(continue, body, exit)
      end
      
      body.build do |builder|
        # calculate coordinates
        x = builder.fdiv(
              builder.si2fp(
                builder.srem(
                  builder.load(index),
                  width),
                LLVM::Float),
              builder.si2fp(width, LLVM::Float))
        y = builder.fdiv(
              builder.si2fp(
                builder.sdiv(
                  builder.load(index),
                  height),
                LLVM::Float),
              builder.si2fp(width, LLVM::Float))
        pt = Point2D[
               FloatingData[x],
               FloatingData[y]]
        
        # evaluate image at pt
        color = yield pt
        
        float_ptr = LLVM::Pointer(LLVM::Float)
        location = builder.mul(
                     builder.load(index),
                     LLVM::Int(16))
        
        # red
        builder.store(
          color.r.codegen(builder),
          builder.int2ptr(
            builder.add(buffer, location),
            float_ptr))
        
        # green
        builder.store(
          color.g.codegen(builder),
          builder.int2ptr(
            builder.add(
              builder.add(buffer, location),
              LLVM::Int(4)),
            float_ptr))
        
        # blue
        builder.store(
          color.b.codegen(builder), 
          builder.int2ptr(
            builder.add(
              builder.add(buffer, location),
              LLVM::Int(8)),
            float_ptr))
        
        # alpha
        builder.store(
          color.a.codegen(builder),
          builder.int2ptr(
            builder.add(
              builder.add(buffer, location),
              LLVM::Int(12)),
            float_ptr))
        
        # increment pixel buffer index
        builder.store(
          builder.add(
            builder.load(index),
            LLVM::Int(1)),
          index)
        
        builder.br(test)
      end
      
      exit.build do |builder|
        builder.ret(LLVM::Int(0))
      end
    end
    mod.dump
    mod.verify!
    
    ee = LLVM::ExecutionEngine.create_jit_compiler(
           LLVM::ModuleProvider.for_existing_module(mod))
    
    # pass selection based on Rubinius jit compiler
    pm = LLVM::PassManager.new(ee)
    pm << :mem2reg <<
          :instcombine <<
          :reassociate <<
          :gvn <<
          :dse <<
          :instcombine <<
          :simplifycfg <<
          :gvn <<
          :dse <<
          :scalarrepl <<
          :simplifycfg <<
          :instcombine <<
          :simplifycfg <<
          :dse <<
          :simplifycfg <<
          :instcombine
    pm.run(mod)
    
    render_callback = ee.pointer_to_global(mod.functions[:animate])
    
    argc = argv.size
    FFI::MemoryPointer.new(:pointer, argc) do |argv_p|
      argv.each_with_index do |arg, i|
        argv_p[i].put_pointer(0, FFI::MemoryPointer.from_string(arg))
      end
      C.animate(render_callback, argc, argv_p)
    end
  end
  
  def init!
    LLVM.init_x86
  end
  
  def module
    LLVM::Module.create("Anima")
  end
end

if __FILE__ == $0
  include Anima
  
  init!
  animate! do |p|
    RGBA[1 - p.x, p.y, p.x, 0]
  end
end
