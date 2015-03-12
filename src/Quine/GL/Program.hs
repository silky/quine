{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE DeriveGeneric              #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
--------------------------------------------------------------------
-- |
-- Copyright :  (c) 2014 Edward Kmett and Jan-Philip Loos
-- License   :  BSD2
-- Maintainer:  Edward Kmett <ekmett@gmail.com>
-- Stability :  experimental
-- Portability: non-portable
--
--------------------------------------------------------------------
module Quine.GL.Program 
  ( Program(..)
  , attachShader
  , detachShader
  , attachedShaders
  , numAttachedShaders
  , linkProgram
  , linkStatus
  , programSeparable
  , validateProgram
  , validateStatus
  , programInfoLog
  , programIsDeleted
  , numActiveAttributes
  , activeAttributeMaxLength
  , numActiveUniforms
  , activeUniformMaxLength
  , activeAtomicCounterBuffers
  , programBinaryLength
  , programComputeWorkGroupSize
  , transformFeedbackVaryingsMaxLength
  , transformFeedbackBufferMode
  , numTransformFeedbackVaryings
  , geometryVerticesOut
  , geometryInputType
  , geometryOutputType
  , currentProgram
  -- * Separable Program
  , createShaderProgramInclude
  ) where

import Control.Applicative
import Control.Monad
import Control.Monad.IO.Class
import qualified Data.ByteString as Strict
import qualified Data.ByteString.Internal as Strict
import qualified Data.ByteString.Lazy as Lazy
import Data.Coerce
import Data.Data
import Data.Default
import Foreign.Marshal.Alloc
import Foreign.Marshal.Array
import Foreign.Ptr
import Foreign.Storable
import Data.StateVar
import GHC.Generics
import Graphics.GL.Core45
import Graphics.GL.Types
import Quine.GL.Object
import Quine.GL.Shader

newtype Program = Program GLuint deriving (Eq,Ord,Show,Read,Typeable,Data,Generic)

instance Object Program where
  object = coerce
  isa p = (GL_FALSE /=) `liftM` glIsProgram (coerce p)
  delete p = glDeleteProgram (coerce p)

instance Gen Program where
  gen = liftM Program glCreateProgram

instance Default Program where
  def = Program 0


-- * Attaching Shaders

attachShader :: MonadIO m => Program -> Shader -> m ()
attachShader (Program p) (Shader s) = glAttachShader p s

detachShader :: MonadIO m => Program -> Shader -> m ()
detachShader (Program p) (Shader s) = glDetachShader p s

-- | @'numAttachedShaders' program@ returns the number of shader objects attached to @program@.
numAttachedShaders :: MonadIO m => Program -> m Int
numAttachedShaders p = fromIntegral `liftM` get (programParameter1 p GL_ATTACHED_SHADERS)

attachedShaders :: MonadIO m => Program -> m [Shader]
attachedShaders p = do
  numShaders <- fromIntegral `liftM` get (programParameter1 p GL_ATTACHED_SHADERS)
  ids <- liftIO $ allocaArray (fromIntegral numShaders) $ \buf -> do
    glGetAttachedShaders (object p) numShaders nullPtr buf
    peekArray (fromIntegral numShaders) buf
  return $ map Shader ids

-- * Properties

programParameter1 :: Program -> GLenum -> StateVar GLint
programParameter1 p parm = StateVar g s where
  g = alloca $ liftM2 (>>) (glGetProgramiv (coerce p) parm) peek
  s = glProgramParameteri (coerce p) parm

linkProgram :: MonadIO m => Program -> m ()
linkProgram = glLinkProgram . object

programInfoLog :: MonadIO m => Program -> m Strict.ByteString
programInfoLog p = liftIO $ do
  l <- fromIntegral <$> get (programParameter1 p GL_INFO_LOG_LENGTH)
  if l <= 1
    then return Strict.empty
    else liftIO $ alloca $ \pl -> do
      Strict.createUptoN l $ \ps -> do
        glGetProgramInfoLog (object p) (fromIntegral l) pl (castPtr ps)
        return $ l-1

-- | @'programIsDeleted' program@ returns 'True' if @program@ is currently flagged for deletion, 'False' otherwise.
programIsDeleted :: MonadIO m => Program -> m Bool
programIsDeleted p = (GL_FALSE /=) `liftM` get (programParameter1 p GL_DELETE_STATUS)

-- | @'linkStatus' program@ returns 'True'if the last link operation on @program@ was successful, 'False' otherwise.
linkStatus :: MonadIO m => Program -> m Bool
linkStatus p = (GL_FALSE /=) `liftM` get (programParameter1 p GL_LINK_STATUS)

-- | Check if the shader is a separable program
-- separable shader programs can be created by 'createShaderProgram'
programSeparable :: Program -> StateVar Bool
programSeparable p = mapStateVar toGLBool fromGLBool $ programParameter1 p GL_PROGRAM_SEPARABLE where
  toGLBool b = if b then GL_TRUE else GL_FALSE
  fromGLBool b = if b == GL_TRUE then True else False 

-- * Validation

-- | @'validateProgram' program@ checks to see whether the executables contained in @program@ can execute given the current OpenGL state. The information generated by the validation process will be stored in @program@'s information log. The validation information may consist of an empty string, or it may be a string containing information about how the current program object interacts with the rest of current OpenGL state. This provides a way for OpenGL implementers to convey more information about why the current program is inefficient, suboptimal, failing to execute, and so on.
--
validateProgram :: MonadIO m => Program -> m ()
validateProgram (Program p) = glValidateProgram p

-- | @'validateStatus' program@ returns 'True' if the last validation operation on @program@ was successful, and 'False' otherwise.
--
-- If 'True', @program@ is guaranteed to execute given the current state. Otherwise, @program@ is guaranteed to not execute.
validateStatus :: MonadIO m => Program -> m Bool
validateStatus p = (GL_FALSE /=) `liftM` get (programParameter1 p GL_VALIDATE_STATUS)

-- * Atomic Counter Buffers

-- | @'activeAtomicCounterBuffers' program@ returns the number of active attribute atomic counter buffers used by @program@.
activeAtomicCounterBuffers :: MonadIO m => Program -> m Int
activeAtomicCounterBuffers p = fromIntegral `liftM` get (programParameter1 p GL_ACTIVE_ATOMIC_COUNTER_BUFFERS)

-- * Attributes

-- data Attribute = Attribute { attributeName :: String, attributeType :: GLenum, attributeSize :: Int }

-- | @'numActiveAttributes' program@ returns the number of active attribute variables for @program@.
numActiveAttributes :: MonadIO m => Program -> m Int
numActiveAttributes p = fromIntegral `liftM` get (programParameter1 p GL_ACTIVE_ATTRIBUTES)

-- | @'activeAttributeMaxLength' program@  returns the length of the longest active attribute name for @program@, including the null termination character (i.e., the size of the character buffer required to store the longest attribute name). If no active attributes exist, 0 is returned.
activeAttributeMaxLength :: MonadIO m => Program -> m Int
activeAttributeMaxLength p = fromIntegral `liftM` get (programParameter1 p GL_ACTIVE_ATTRIBUTE_MAX_LENGTH)

-- * Uniforms

-- | @'numActiveUniforms' returns the number of active uniform variables for @program@.
numActiveUniforms :: MonadIO m => Program -> m Int
numActiveUniforms p = fromIntegral `liftM` get (programParameter1 p GL_ACTIVE_UNIFORMS)

-- | @'activeUniformMaxLength' program@  returns the length of the longest active uniform variable name for @program@, including the null termination character (i.e., the size of the character buffer required to store the longest uniform variable name). If no active uniform variables exist, 0 is returned.
activeUniformMaxLength :: MonadIO m => Program -> m Int
activeUniformMaxLength p = fromIntegral `liftM` get (programParameter1 p GL_ACTIVE_ATTRIBUTE_MAX_LENGTH)

-- * Binary

-- | @'programBinaryLength' program@ return the length of the program binary, in bytes, that will be returned by a call to @glGetProgramBinary@. When a progam's @linkStatus@ is False, its program binary length is 0.
programBinaryLength :: MonadIO m => Program -> m Int
programBinaryLength p = fromIntegral `liftM` get (programParameter1 p GL_PROGRAM_BINARY_LENGTH)

-- * Compute Workgroups

-- | @'programComputeWorkgroupSize' program@ returns three integers containing the local work group size of the compute program as specified by its input layout qualifier(s). @program@ must be the name of a program object that has been previously linked successfully and contains a binary for the compute shader stage.
programComputeWorkGroupSize :: MonadIO m => Program -> m (Int, Int, Int)
programComputeWorkGroupSize (Program p) = liftIO $ allocaArray 3 $ \q -> do
  glGetProgramiv p (GL_COMPUTE_WORK_GROUP_SIZE) q
  a <- peek q
  b <- peekElemOff q 1
  c <- peekElemOff q 2
  return (fromIntegral a, fromIntegral b, fromIntegral c)

-- * Transform Feedback

-- | @'transformFeedbackBufferMode' program@ returns a symbolic constant indicating the buffer mode for @program@ used when transform feedback is active. This may be 'GL_SEPARATE_ATTRIBS' or 'GL_INTERLEAVED_ATTRIBS'.
transformFeedbackBufferMode :: MonadIO m => Program -> m GLenum
transformFeedbackBufferMode p = fromIntegral `liftM` get (programParameter1 p GL_TRANSFORM_FEEDBACK_BUFFER_MODE)

-- | @'numTransformFeedbackVaryings' program@ returns the number of varying variables to capture in transform feedback mode for the @program@.
numTransformFeedbackVaryings :: MonadIO m => Program -> m Int
numTransformFeedbackVaryings p = fromIntegral `liftM` get (programParameter1 p GL_TRANSFORM_FEEDBACK_VARYINGS)

-- | @'transformFeedbackVaryingsMaxLength' program@ returns the length of the longest variable name to be used for transform feedback, including the null-terminator.
transformFeedbackVaryingsMaxLength :: MonadIO m => Program -> m Int
transformFeedbackVaryingsMaxLength p = fromIntegral `liftM` get (programParameter1 p GL_TRANSFORM_FEEDBACK_VARYINGS)

-- * Geometry Shaders

-- | @'geometryVerticesOut' program@ returns the maximum number of vertices that the geometry shader in @program@ will output.
geometryVerticesOut :: MonadIO m => Program -> m Int
geometryVerticesOut p = fromIntegral `liftM` get (programParameter1 p GL_GEOMETRY_VERTICES_OUT)


-- | @'geometryInputType' program@ returns a symbolic constant indicating the primitive type accepted as input to the geometry shader contained in @program@.
geometryInputType :: MonadIO m => Program -> m GLenum
geometryInputType p = fromIntegral `liftM` get (programParameter1 p GL_GEOMETRY_INPUT_TYPE)

-- | @'geometryOutputType' program@ returns a symbolic constant indicating the primitive type that will be output by the geometry shader contained in @program@.
geometryOutputType :: MonadIO m => Program -> m GLenum
geometryOutputType p = fromIntegral `liftM` get (programParameter1 p GL_GEOMETRY_OUTPUT_TYPE)

currentProgram :: StateVar Program
currentProgram = StateVar
  (fmap (Program . fromIntegral) $ alloca $ liftM2 (>>) (glGetIntegerv GL_CURRENT_PROGRAM) peek)
  (glUseProgram . object)

-- * Separable Program

-- | @'createSeparableProgram' shaderType source paths@ emulates the missing OpenGL functionality to
-- create a separable 'Program' from source with 'glCreateShaderProgram' but 
-- with 'GL_ARB_shading_language_include' support.
createShaderProgramInclude :: MonadIO m => ShaderType -> Lazy.ByteString -> [FilePath] -> m Program
createShaderProgramInclude shaderTy source paths = do
  s <- createShader shaderTy
  shaderSource s $= source
  compileShaderInclude s paths
  compiled <- compileStatus s
  prog <- gen
  when compiled $ do
    programSeparable prog $= True
    attachShader prog s
    linkProgram prog
    detachShader prog s
  delete s
  return prog

