# frozen_string_literal: true

module Gitlab
  module Git
    # Methods for committing. Use all these methods only mutexed with the git
    # repository as the key.
    module Committing
      class Error < StandardError; end
      class InvalidPathError < Error; end

      # This error is thrown when attempting to commit on a branch whose HEAD has
      # changed.
      class HeadChangedError < Error
        attr_reader :options
        def initialize(message, options)
          super(message)
          @options = options
        end
      end

      # Create a file in repository and return commit sha
      #
      # options should contain the following structure:
      #   file: {
      #     content: 'Lorem ipsum...',
      #     path: 'documents/story.txt'
      #   },
      #   author: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   committer: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   commit: {
      #     message: 'Wow such commit',
      #     branch: 'master',    # optional - default: 'master'
      #     update_ref: false    # optional - default: true
      #   }
      def create_file(options, previous_head_sha = nil)
        commit_multichange(convert_options(options, :create), previous_head_sha)
      end

      # Change (contents and path of) file in repository and return commit sha
      #
      # options should contain the following structure:
      #   file: {
      #     content: 'Lorem ipsum...',
      #     path: 'documents/story.txt',
      #     previous_path: 'documents/old_story.txt' # optional - used for renaming while updating
      #   },
      #   author: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   committer: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   commit: {
      #     message: 'Wow such commit',
      #     branch: 'master',    # optional - default: 'master'
      #     update_ref: false    # optional - default: true
      #   }
      def update_file(options, previous_head_sha = nil)
        commit_multichange(convert_options(options, :update), previous_head_sha)
      end

      # Remove file from repository and return commit sha
      #
      # options should contain the following structure:
      #   file: {
      #     path: 'documents/story.txt'
      #   },
      #   author: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   committer: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   commit: {
      #     message: 'Remove FILENAME',
      #     branch: 'master'    # optional - default: 'master'
      #   }
      def remove_file(options, previous_head_sha = nil)
        commit_multichange(convert_options(options, :remove), previous_head_sha)
      end

      # Rename file from repository and return commit sha
      # This does not change the file content.
      #
      # options should contain the following structure:
      #   file: {
      #     previous_path: 'documents/old_story.txt'
      #     path: 'documents/story.txt'
      #   },
      #   author: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   committer: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   commit: {
      #     message: 'Rename FILENAME',
      #     branch: 'master'    # optional - default: 'master'
      #   }
      #
      def rename_file(options, previous_head_sha = nil)
        commit_multichange(convert_options(options, :rename), previous_head_sha)
      end

      # Create a new directory with a .gitkeep file. Creates
      # all required nested directories (i.e. mkdir -p behavior)
      #
      # options should contain the following structure:
      #   author: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   committer: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   commit: {
      #     message: 'Wow such commit',
      #     branch: 'master',    # optional - default: 'master'
      #     update_ref: false    # optional - default: true
      #   }
      def mkdir(path, options, previous_head_sha = nil)
        options[:file] = {path: path}
        commit_multichange(convert_options(options, :mkdir), previous_head_sha)
      end

      # Apply multiple file changes to the repository
      #
      # options should contain the following structure:
      #   files: {
      #     [{content: 'Lorem ipsum...',
      #       path: 'documents/story.txt',
      #       action: :create},
      #      {content: 'New Lorem ipsum...',
      #       path: 'documents/old_story',
      #       previus_path: 'documents/really_old_story.txt', # optional - moves the file from +previous_path+ to +path+ if this is given
      #       action: :update},
      #      {path: 'documents/obsolet_story.txt',
      #       action: :remove},
      #      {path: 'documents/old_story',
      #       previus_path: 'documents/really_old_story.txt',
      #       action: :rename},
      #      {path: 'documents/secret',
      #       action: :mkdir}
      #     ]
      #     }
      #   },
      #   author: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   committer: {
      #     email: 'user@example.com',
      #     name: 'Test User',
      #     time: Time.now    # optional - default: Time.now
      #   },
      #   commit: {
      #     message: 'Wow such commit',
      #     branch: 'master',    # optional - default: 'master'
      #     update_ref: false    # optional - default: true
      #   }
      def commit_multichange(options, previous_head_sha = nil)
        commit_with(options, previous_head_sha) do |index|
          options[:files].each do |file|
            file_options = {}
            file_options[:file_path] = file[:path] if file[:path]
            file_options[:content] = file[:content] if file[:content]
            file_options[:encoding] = file[:encoding] if file[:encoding]
            case file[:action]
            when :create
              index.create(file_options)
            when :rename
              file_options[:previous_path] = file[:previous_path]
              file_options[:content] ||=
                blob(options[:commit][:branch], file[:previous_path]).data
              index.move(file_options)
            when :update
              previous_path = file[:previous_path]
              if previous_path && previous_path != path
                file_options[:previous_path] = previous_path
                index.move(file_options)
              else
                index.update(file_options)
              end
            when :remove
              index.delete(file_options)
            when :mkdir
              index.create_dir(file_options)
            end
          end
        end
      end

      protected

      # TODO: Instead of comparing the HEAD with the previous commit_sha,
      # actually try merging and only raise if there is a conflict. Add the
      # merge conflict to the Error.
      # See issue https://github.com/ontohub/ontohub-backend/issues/97.
      def prevent_overwriting_previous_changes(options, previous_head_sha)
        return unless conflict?(options, previous_head_sha)
        raise HeadChangedError.new('The branch has changed since editing.',
                                   options)
      end

      # Converts the options from a single change commit to a multi change
      # commit.
      def convert_options(options, action)
        converted = options.dup
        converted.delete(:file)
        converted[:files] = [options[:file].merge(action: action)]
        converted
      end

      def conflict?(options, previous_head_sha)
        !previous_head_sha.nil? &&
          branch_sha(options[:commit][:branch]) != previous_head_sha
      end

      def insert_defaults(options)
        options[:author][:time] ||= Time.now
        options[:committer][:time] ||= Time.now
        options[:commit][:branch] ||= 'master'
        options[:commit][:update_ref] = true if options[:commit][:update_ref].nil?
        normalize_ref(options)
      end

      def normalize_ref(options)
        return if options[:commit][:branch].start_with?('refs/')
        options[:commit][:branch] = 'refs/heads/' + options[:commit][:branch]
      end

      # This method does the actual committing. Use this mutexed with the git
      # repository as the key.
      # rubocop:disable Metrics/AbcSize
      # rubocop:disable Metrics/CyclomaticComplexity
      # rubocop:disable Metrics/PerceivedComplexity
      # rubocop:disable Metrics/MethodLength
      def commit_with(options, previous_head_sha)
        insert_defaults(options)
        prevent_overwriting_previous_changes(options, previous_head_sha)

        commit = options[:commit]
        ref = commit[:branch]
        ref = 'refs/heads/' + ref unless ref.start_with?('refs/')
        update_ref = commit[:update_ref].nil? ? true : commit[:update_ref]

        index = Gitlab::Git::Index.new(gitlab)

        parents = []
        unless empty?
          rugged_ref = rugged.references[ref]
          unless rugged_ref
            raise Gitlab::Git::Repository::InvalidRef, 'Invalid branch name'
          end
          last_commit = rugged_ref.target
          index.read_tree(last_commit.tree)
          parents = [last_commit]
        end

        yield(index)

        opts = {}
        opts[:tree] = index.write_tree
        opts[:author] = options[:author]
        opts[:committer] = options[:committer]
        opts[:message] = commit[:message]
        opts[:parents] = parents
        opts[:update_ref] = ref if update_ref

        Rugged::Commit.create(rugged, opts)
      end
      # rubocop:enable Metrics/AbcSize
      # rubocop:enable Metrics/CyclomaticComplexity
      # rubocop:enable Metrics/PerceivedComplexity
      # rubocop:enable Metrics/MethodLength
    end
  end
end
