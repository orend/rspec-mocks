module RSpec
  module Mocks
    # Represents a method on an object that may or may not be defined.
    # The method may be an instance method on a module or a method on
    # any object.
    #
    # @private
    class MethodReference
      def initialize(object_reference, method_name)
        @object_reference = object_reference
        @method_name = method_name
      end

      # A method is implemented if sending the message does not result in
      # a `NoMethodError`. It might be dynamically implemented by
      # `method_missing`.
      def implemented?
        @object_reference.when_loaded do |m|
          method_implemented?(m)
        end
      end

      # Returns true if we definitively know that sending the method
      # will result in a `NoMethodError`.
      #
      # This is not simply the inverse of `implemented?`: there are
      # cases when we don't know if a method is implemented and
      # both `implemented?` and `unimplemented?` will return false.
      def unimplemented?
        @object_reference.when_loaded do |m|
          return !implemented?
        end

        # If it's not loaded, then it may be implemented but we can't check.
        false
      end

      # A method is defined if we are able to get a `Method` object for it.
      # In that case, we can assert against metadata like the arity.
      def defined?
        @object_reference.when_loaded do |m|
          method_defined?(m)
        end
      end

      def with_signature
        if original = original_method
          yield MethodSignature.new(original)
        end
      end

      def visibility
        @object_reference.when_loaded do |m|
          return visibility_from(m)
        end

        # When it's not loaded, assume it's public. We don't want to
        # wrongly treat the method as private.
        :public
      end

      private

      def original_method
        @object_reference.when_loaded do |m|
          self.defined? && find_method(m)
        end
      end

      def self.instance_method_visibility_for(klass, method_name)
        if klass.public_method_defined?(method_name)
          :public
        elsif klass.private_method_defined?(method_name)
          :private
        elsif klass.protected_method_defined?(method_name)
          :protected
        end
      end

      class << self
        alias method_defined_at_any_visibility? instance_method_visibility_for
      end

      def self.method_visibility_for(object, method_name)
        instance_method_visibility_for(class << object; self; end, method_name).tap do |vis|
          # If the method is not defined on the class, `instance_method_visibility_for`
          # returns `nil`. However, it may be handled dynamically by `method_missing`,
          # so here we check `respond_to` (passing false to not check private methods).
          #
          # This only considers the public case, but I don't think it's possible to
          # write `method_missing` in such a way that it handles a dynamic message
          # with private or protected visibility. Ruby doesn't provide you with
          # the caller info.
          return :public if vis.nil? && object.respond_to?(method_name, false)
        end
      end
    end

    # @private
    class InstanceMethodReference < MethodReference
      private
      def method_implemented?(mod)
        MethodReference.method_defined_at_any_visibility?(mod, @method_name)
      end

      # Ideally, we'd use `respond_to?` for `method_implemented?` but we need a
      # reference to an instance to do that and we don't have one.  Note that
      # we may get false negatives: if the method is implemented via
      # `method_missing`, we'll return `false` even though it meets our
      # definition of "implemented". However, it's the best we can do.
      alias method_defined? method_implemented?

      # works around the fact that repeated calls for method parameters will
      # falsely return empty arrays on JRuby in certain circumstances, this
      # is necessary here because we can't dup/clone UnboundMethods.
      #
      # This is necessary due to a bug in JRuby prior to 1.7.5 fixed in:
      # https://github.com/jruby/jruby/commit/99a0613fe29935150d76a9a1ee4cf2b4f63f4a27
      if RUBY_PLATFORM == 'java' && JRUBY_VERSION.split('.')[-1].to_i < 5
        def find_method(mod)
          mod.dup.instance_method(@method_name)
        end
      else
        def find_method(mod)
          mod.instance_method(@method_name)
        end
      end

      def visibility_from(mod)
        MethodReference.instance_method_visibility_for(mod, @method_name)
      end
    end

    # @private
    class ObjectMethodReference < MethodReference
      private
      def method_implemented?(object)
        object.respond_to?(@method_name, true)
      end

      def method_defined?(object)
        (class << object; self; end).method_defined?(@method_name)
      end

      def find_method(object)
        object.method(@method_name)
      end

      def visibility_from(object)
        MethodReference.method_visibility_for(object, @method_name)
      end
    end
  end
end
